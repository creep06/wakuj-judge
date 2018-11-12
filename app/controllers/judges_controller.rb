require 'docker'

class JudgesController < ApplicationController
	def judge
		logger.debug("postを受け取ったぜ")
		# logger.debug(params[:code])

		# paramsを元にジャッジする
		code = params[:code]
		lang = params[:language]
		input = "1"
		ans = "HELLO\n"

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

		# TODO ↓これの目的なに？
		# sleep(0.005)

		# TODO
		# テストケースを1個ずつダウンロードして実行
		# 今の所とりあえずinputのみで試してansと照合してる
		container.store_file("/tmp/input.txt", input)

		logger.debug("テストケースを実行するぜ")
		result = container.exec(["timeout", "4", "bash", "-c", "time #{exec_cmd} < input.txt"])
		logger.debug("テストケースを実行したぜ")
		container.delete(force: true)
		logger.debug("コンテナ削除完了だぜ")


		case result.last
		when 0
			time = result[1][0].split[3].split("m")[1].to_f
			case
			when (result[0][0] == ans && time <= 2.0) then logger.debug('AC')
			when (result[0][0] == ans && time >	2.0) then logger.debug('TLE')
			when (result[0][0] != ans) then logger.debug('WA')
			end
			logger.debug(result[1][0].split[3].split("m")[1])
		else
			logger.debug('RE')
			logger.debug(result[1][0].split[3].split("m")[1])
		end

	end


	# 言語に応じたdockerコンテナを作成
	def create_container image_name, file_name, code
		memory = 500 * 1024 * 1024
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
