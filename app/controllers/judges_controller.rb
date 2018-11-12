require 'docker'
require 'google_drive'
require 'net/http'

class JudgesController < ApplicationController
	def judge
		logger.debug("postを受け取ったぜ")

		logger.debug(params)

		# paramsを元にジャッジする
		code = params[:code]
		lang = params[:language]

		# 言語で分岐
		logger.debug("コンテナを作るぜ")

		case lang
		when 'c'
			file_name = "main.c"
			container = create_container('gcc:latest', file_name, code)
			ce = container.exec(["timeout", "10", "bash", "-c", "gcc #{file_name}"]).last != 0
			exec_cmd = './a.out'
		when 'cpp'
			file_name = "main.cpp"
			container = create_container('gcc:latest', file_name, code)
			logger.debug("コンテナを作ったぜ")
			ce = container.exec(["timeout", "10", "bash", "-c", "g++ #{file_name}"]).last != 0
			logger.debug("コンパイルしたぜ")
			exec_cmd = './a.out'
		when 'py'
			file_name = "main.py"
			container = create_container('python:latest', file_name, code)
			exec_cmd = "python #{file_name}"
		when 'rb'
			file_name = "main.rb"
			container = create_container('ruby:latest', file_name, code)
			exec_cmd = "ruby #{file_name}"
		end


		# コンパイル言語かつコンパイルに失敗した場合その時点で終了
		if ce
			logger.debug("コンパイル失敗だぜ")
			container.delete(force: true)
			return 'CE'
		end

		logger.debug("コンパイル成功だぜ")

		# TODO
		# MLEの判定
		# 使用メモリの求め方がわからんから後回し
		# 今のところメモリ使いすぎたらREになる？

		# 時間はms単位で扱ってることに注意 メモリはMB
		tlim = params[:time_limit].to_i
		tlim2 = tlim * 2
		mlim = params[:memory_limit].to_i
		testnum = params[:testcases_number].to_i
		problem_id = params[:problem_id]

		# gdriveにログイン(?)
		session = GoogleDrive::Session.from_config("config/gdrive.json")

		# 判定→数字の変換表 数字がデカイほど強い
		# 一番強いやつをこのsubmissionの総合的なverdictとして返す
		conv = {"AC"=>0, "RE"=>1, "TLE"=>2, "WA"=>10}
		totalver = "AC"

		# テストケースを1個ずつダウンロードして実行
		for i in 1..(testnum)
			# テストケースを名前で検索して一時的に保存
			name = problem_id + "-" + i.to_s
			inputfile = session.file_by_title("i" + name + ".txt")
			inputfile.download_to_file("tmp/testcases/in.txt")
			input = File.open("tmp/testcases/in.txt").read
			outputfile = session.file_by_title("o" + name + ".txt")
			outputfile.download_to_file("tmp/testcases/out.txt")
			ans = File.open("tmp/testcases/out.txt").read

			# 実行
			container.store_file("/tmp/input.txt", input)
			logger.debug("テストケース" + i.to_s)
			res = container.exec(["timeout", "#{tlim*2}", "bash", "-c", "time #{exec_cmd} < input.txt"])

			# おまじない
			# ぐちゃぐちゃなexecから頑張って出力と実行時間を取り出してる
			output, tmp = res.join.split("\nreal\t")
			time = (tmp.split("\nuser\t")[1].split('m')[1].split('s')[0].to_f*1000).to_i
			finished = tmp.last

			# TODO
			# ↓だと一部のTLEもREに含まれてしまう
			# もうちょい正確にverdictを切り替えたい
			# 実行が正しく完了した場合
			if finished
				case
				when (output != ans) then ver = "WA"
				when (output == ans && time <= tlim) then ver = "AC"
				when (output == ans && time > tlim) then ver = "TLE"
				end
			# 正しく完了しなかった場合
			else
				ver = "RE"
			end

			totalver = ver if conv[totalver] < conv[ver]

			logger.debug("テストケースを実行したぜ")
			logger.debug("結果: " + ver)
			logger.debug("時間: " + time.to_s) if ver!='CE'

			# webサーバーに結果をpost
			uri = URI.parse("http://localhost:3000/result")
			http = Net::HTTP.new(uri.host, uri.port)
			http.use_ssl = false
			http.verify_mode = OpenSSL::SSL::VERIFY_NONE
			req = Net::HTTP::Post.new(uri.path)
			req.set_form_data({
				name: name,
				verdict: ver,
				time: time,
				memory: 0,
				submission_id: params[:submission_id]
			})
			http.request(req)
		end

		container.delete(force: true)
		logger.debug("コンテナ削除完了だぜ")

		return totalver
	end


	# 言語に応じたdockerコンテナを作成
	def create_container image_name, file_name, code
		# TODO
		# とりあえず256MB確保してるけどこれでサーバーのメモリが足りなくなったらどうなるんだろう
		memory = 256 * 1024 * 1024
		options = {
			'Image' => image_name,
			'Tty' => true,
			'HostConfig' => {
				'Memory' => memory,
				'PidsLimit' => 10
			},
			'WorkingDir' => '/tmp'
		}
		container = Docker::Container.create(options)
		container.start
		container.store_file("/tmp/#{file_name}", code)
		return container
	end



end
