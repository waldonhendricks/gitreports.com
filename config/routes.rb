GitReports::Application.routes.draw do

  root 'pages#home'

  # Pages
  get '/profile', to: 'pages#profile', as: 'profile'
  get '/tutorial', to: 'pages#tutorial', as: 'tutorial'
  get '/about', to: 'pages#about', as: 'about'

  # Authentication routes
  get '/login', to: 'authentications#login', as: 'login'
  get '/github_callback', to: 'authentications#callback'
  get '/logout', to: 'authentications#logout', as: 'logout'
  get '/login_rate_limited', to: 'authentications#login_rate_limited', as: 'login_rate_limited'

  # Repository routes
  scope :issue do
    get ':username/:repositoryname', to: 'repositories#repository', as: 'repository_public', repositoryname: /[^\/]+/
    post ':username/:repositoryname', to: 'repositories#submit', repositoryname: /[^\/]+/
    get ':username/:repositoryname/submitted', to: 'repositories#submitted', as: 'submitted', repositoryname: /[^\/]+/
  end

  resources :repositories do
    post 'activate'
    post 'deactivate'
  end

  get '/load_status', to: 'repositories#load_status'

end
