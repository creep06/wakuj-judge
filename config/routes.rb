Rails.application.routes.draw do
	post '/judge', to: 'judges#judge'
end
