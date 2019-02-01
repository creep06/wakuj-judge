require 'docker'
#require 'google_drive'
require 'net/http'

class JudgesController < ApplicationController
	def judge
		# 時間はms単位で扱ってることに注意 メモリはMB
		code = params[:code]
		lang = params[:language]
		time_limit = params[:time_limit].to_i
		memory_limit = params[:memory_limit].to_i * 1024
		testcases_number = params[:testcases_number].to_i
		problem_id = params[:problem_id]
		submission_id = params[:submission_id]

		# 言語毎の初期化
		case lang
		when 'c'
			file_name = 'main.c'
			container = create_container('creep04/gccgtime:latest', file_name, code)
			ce = container.exec(['timeout', '10', 'bash', '-c', "gcc #{file_name}"]).last != 0
			exec_cmd = './a.out'
		when 'cpp'
			file_name = 'main.cpp'
			container = create_container('creep04/gccgtime:latest', file_name, code)
			ce = container.exec(['timeout', '10', 'bash', '-c', "g++ #{file_name}"]).last != 0
			exec_cmd = './a.out'
			memory_adjustment = 2800
		when 'java'
			file_name = 'main.java'
			container = create_container('openjdk:8', file_name, code)
			temp = container.exec(['timeout', '10', 'bash', '-c', "javac #{file_name}"])
			logger.debug(temp.inspect)
			ce = temp.last != 0
			exec_cmd = 'java main'
		when 'py'
			file_name = 'main.py'
			container = create_container('creep04/pythongtime:latest', file_name, code)
			exec_cmd = "python #{file_name}"
			memory_adjustment = 5000
		when 'rb'
			file_name = 'main.rb'
			container = create_container('creep04/rubygtime:latest', file_name, code)
			exec_cmd = "ruby #{file_name}"
			memory_adjustment = 7000
		end

		# コンパイル言語かつコンパイルに失敗した場合その時点で終了
		if ce
			container.delete(force: true)
			finish_judging('CE', 0, 0)
			return
		end

		# 判定→数字の変換表
		# 提出そのものの総合的な判定はこの表で数字が一番デカイやつになる
		verdict_conversion = {'AC'=>0, 'MLE'=>1, 'TLE'=>2, 'RE'=>3, 'WA'=>10}
		total_verdict = 'AC'
		max_time = 0
		max_memory = 0

		for i in 1..(testcases_number)
			# 入力と答えのtextを作る + コンテナで入力を実行して出力を受け取る
			testcase_name = problem_id + '-' + i.to_s
			testcase_input = File.open("#{Rails.root}/public/testcases/#{problem_id}/in/i#{testcase_name}.txt").read
			testcase_answer = File.open("#{Rails.root}/public/testcases/#{problem_id}/out/o#{testcase_name}.txt").read
			container.store_file("/tmp/input.txt", testcase_input)
			result = container.exec(['timeout', "#{time_limit.to_f/1000}", 'bash', '-c', "/usr/bin/time -f \"!!!%U %M!!!\" #{exec_cmd} < input.txt"]).join.split('!!!')
			logger.debug(result.inspect)

			# 時間内にコンテナが応答しなかった場合
			if result.size == 1
				verdict = 'TLE'
				max_time = time = time_limit
				memory = 0
			elsif result[0].start_with?("Command terminated")
				verdict = 'RE'
				time = memory = 0
			else
				output, tmp = result[0], result[1]
				time = (result[1].split(' ')[0].to_f*1000).to_i
				memory = result[1].split(' ')[1].to_i - memory_adjustment
				memory = 10 if memory < 0
				output = cut_last_garbage(output)
				testcase_answer = cut_last_garbage(testcase_answer)

				if (memory>memory_limit)
					verdict = 'MLE'
				else
					verdict = (output == testcase_answer ? 'AC' : 'WA')
				end
				max_time = time if max_time < time
				max_memory = memory if max_memory < memory
			end

			# 変換表を使ってtotal_verdictを更新
			old_number = verdict_conversion[total_verdict]
			new_number = verdict_conversion[verdict]
			total_verdict = verdict if old_number < new_number

			# webサーバーに結果をPOST
			http, req = brand_new_post('result')
			req.set_form_data({
				name: testcase_name,
				verdict: verdict,
				time: time,
				memory: memory,
				submission_id: submission_id
			})
			http.request(req)
		end

		container.delete(force: true)
		finish_judging(total_verdict, max_time, max_memory)
	end


	# 新しいPOSTリクエストを作成
	def brand_new_post controller
		if Rails.env.production?
			uri = URI.parse("https://wakuwaku-judge.herokuapp.com/#{controller}")
		else
			uri = URI.parse("http://localhost:3000/#{controller}")
		end
		http = Net::HTTP.new(uri.host, uri.port)
		http.use_ssl = Rails.env.production?
		http.verify_mode = OpenSSL::SSL::VERIFY_NONE
		return http, Net::HTTP::Post.new(uri.path)
	end


	# 言語に応じたdockerコンテナを作成
	def create_container image_name, file_name, code
		# TODO
		# とりあえず256MB確保してるけどこの確保によってサーバーのメモリが足りなくなったらどうなるんだろう
		memory_allocation = 256 * 1024 * 1024
		options = {
			'Image' => image_name,
			'Tty' => true,
			'HostConfig' => {
				'Memory' => memory_allocation,
				'PidsLimit' => 100
			},
			'WorkingDir' => '/tmp'
		}
		container = Docker::Container.create(options)
		container.start
		container.store_file("/tmp/#{file_name}", code)
		return container
	end


	# webサーバーに総合的な結果をpost
	def finish_judging(verdict, time, memory)
		http, req = brand_new_post('judged')
		req.set_form_data({
			verdict: verdict,
			time: time,
			memory: memory,
			submission_id: params[:submission_id]
		})
		http.request(req)
	end


	# stringの末尾の空白と改行を全て削除
	def cut_last_garbage str
		while true
			fin = true
			while str[-1] == "\n"
				str.slice!(-1)
				fin = false
			end
			while str[-1] == ' '
				str.slice!(-1)
				fin = false
			end
			break if fin
		end
		return str
	end
end
