require_relative 'sinatra_helpers'

module GitHubReminders
	class App < Sinatra::Base
		enable :sessions
		use Rack::Flash, :sweep => true

		set :github_options, {
			:scopes    => "user, admin:repo_hook",
			:secret    => ENV['GITHUB_CLIENT_SECRET'],
			:client_id => ENV['GITHUB_CLIENT_ID'],
		}

		register Sinatra::Auth::Github

		helpers do

			def get_auth_info
				authInfo = {:username => github_user.login, :userID => github_user.id}
			end

		end

		get '/' do
			# authenticate!
			if authenticated? == true
				# @username = github_user.login
				# @gravatar_id = github_user.gravatar_id
				# @fullName = github_user.name
				# @userID = github_user.id

				userExistsYN = Sinatra_Helpers.user_exists?(@userID)

				if userExistsYN == false
					redirect '/signup'
				end

				@registeredHookList = Sinatra_Helpers.registered_hooks_for_user(get_auth_info[:userID])
				@registeredRepoList = Sinatra_Helpers.registered_repos_for_user(get_auth_info[:userID])
				@publicHookList = Sinatra_Helpers.registered_hooks_public_all_users
			else
				flash[:warning] = ["Please login to continue"]
			end
			erb :index
		end

		# /signup is a landing page with a form for the user to sign up.  
		# Server side data validation is done in the /createuser 
		# call to allow for future API use
		get '/signup' do
			if authenticated? == true

				userExistsYN = Sinatra_Helpers.user_exists?(github_user.id)

				if userExistsYN == true
					redirect '/'
				end

				@timezonesList = Sinatra_Helpers.avalaible_timezones
				@githubEmails = Sinatra_Helpers.get_authenticated_github_emails(github_api)
				@githubEmailsVerfiedExistsYN = Sinatra_Helpers.verified_emails_exist?(@githubEmails)

				erb :signup
			else
				flash[:warning] = ["You must be logged in"]
				erb :unauthenticated
			end     
		end

		# Creates a new user in the MongoDB.  Has full logic for 
		# data validations and ensures that there is not already 
		# the same user in the DB
		post '/createuser' do

			post = params[:post]

			if authenticated? == true

				@dangerMessage = []

				userExistsYN = Sinatra_Helpers.user_exists?(github_user.id)

				if userExistsYN == true
					redirect '/'					
				end

				# Server Side validation of the Name, Email, and Timezone data fields
				if post["fullname"].size > 255
					@dangerMessage << "your name is too long.  Must be less than 255 characters"
				end

				if post["fullname"].size == 0
					@dangerMessage << "You must provide a name"
				end

				@githubEmails = Sinatra_Helpers.get_authenticated_github_emails(github_api)
				@githubEmailsVerfiedExistsYN = Sinatra_Helpers.verified_emails_exist?(@githubEmails)
				
				if @githubEmailsVerfiedExistsYN == false 
					@dangerMessage << "You do not have any verified github email addresses.  You must have a GitHub Verified email to continue"
				end

				if @githubEmails.include?(post["email"]) == false
					@dangerMessage << "Invalid Email. You must be a GitHub.com validated email"
				end

				@timezonesList = Sinatra_Helpers.avalaible_timezones
				@timezonesListShort = Sinatra_Helpers.avalaible_timezones(false)

				if @timezonesListShort.include?(post["timezone"]) == false
					@dangerMessage << "invalid timezone."
				end

				# Adds the data to Mongodb.  
				# Success and Error will be returned with a String message
				if @dangerMessage.length == 0 
					createdUser = Sinatra_Helpers.create_user( get_auth_info[:userID], 
												{:username => get_auth_info[:username],
												 :fullname => post["fullname"],
												 :timezone => post["timezone"],
												 :email => post["email"]
												 })

	 				if createdUser[:type] == :success
						@successMessage = [createdUser[:text]]
						redirect '/signup'
					elsif createdUser[:type] == :failure
						@warningMessage = [createdUser[:text]]
					end
				end
				
			erb :signup
			else
				flash[:warning] = ["You must be logged in"]
				erb :unauthenticated
			end  
		end

		# registers a repo for a specific user
		post '/registerrepo' do
			post = params[:post]
			if authenticated? == true
				fullRepoName = "#{post['repousername']}/#{post['reporepository']}"
				
				registeredRepo = Sinatra_Helpers.register_repo_for_user(get_auth_info[:userID], {:fullreponame => fullRepoName})
				if registeredRepo[:type] == :success
					@successMessage = [registeredRepo[:text]]
				elsif registeredRepo[:type] == :failure
					@warningMessage = [registeredRepo[:text]]
				end

				redirect '/'

			# erb :index
			else
				flash[:warning] = ["You must be logged in"]
				erb :unauthenticated
			end 
		end

		# unregister a repo for a specific user
		post '/unregisterrepo' do
			post = params[:post]
			if authenticated? == true
				fullRepoName = "#{post['removerepousername']}/#{post['removereporepository']}"
				
				unregisteredRepo = Sinatra_Helpers.un_register_repo_for_user(get_auth_info[:userID], fullRepoName)

				if unregisteredRepo[:type] == :success
					@successMessage = [unregisteredRepo[:text]]
				elsif unregisteredRepo[:type] == :failure
					@warningMessage = [unregisteredRepo[:text]]
				end

				redirect '/'
			# erb :index
			else
				flash[:warning] = ["You must be logged in"]
				erb :unauthenticated
			end 
		end

		post '/addwebhook' do
			post = params[:post]
			if authenticated? == true
				fullRepoName = "#{post['hookusername']}/#{post['hookrepository']}"
				
				createdHook = Sinatra_Helpers.create_gh_hook(get_auth_info[:userID], fullRepoName, github_api)
				if createdHook[:type] == :success
					@successMessage = [createdHook[:text]]
				elsif createdHook[:type] == :failure
					@warningMessage = [createdHook[:text]]
				end
				redirect '/'
			# erb :index
			else
				flash[:warning] = ["You must be logged in"]
				erb :unauthenticated
			end     
		end

		# Deletes a webhook
		post '/deletewebhook' do
			post = params[:post]
			if authenticated? == true
				fullRepoName = "#{post['removehookusername']}/#{post['removehookrepository']}"
				@successMessage = []
				@warningMessage = []

				ghRemoval, mongoRemoval = Sinatra_Helpers.remove_webhook(get_auth_info[:userID], fullRepoName, github_api)
				
				if ghRemoval[:type] == :success
					@successMessage << ghRemoval[:text]
				elsif ghRemoval[:type] == :failure
					@warningMessage << ghRemoval[:text]
				end
				if mongoRemoval[:type] == :success
					@successMessage << mongoRemoval[:text]
				elsif mongoRemoval[:type] == :failure
					@warningMessage << mongoRemoval[:text]
				end

				redirect '/'
			# erb :index
			else
				flash[:warning] = ["You must be logged in"]
				erb :unauthenticated
			end     
		end


		get '/logout' do
			logout!
			redirect '/'
		end
		get '/login' do
			authenticate!
			redirect '/'
		end
	end
end