class GithubService
  class << self
    def create_or_update_user(access_token)
      return nil if (client = Octokit::Client.new access_token: access_token).rate_limit.remaining < 10

      # Retrieve or update the user
      retrieve_user(client, access_token)
    end

    def load_repositories(access_token)
      # Find user
      user = User.find_by_access_token(access_token)

      # Create client with token
      return nil if (client = Octokit::Client.new access_token: access_token, auto_paginate: true).rate_limit.remaining < 10

      # Add repos and remove user from any repos they no longer have access to
      remove_outdated(user, user.repositories.pluck(:github_id) - add_repos(client.repos, user) - add_orgs(client.orgs, user))
    end

    def submit_issue(repo_id, sub_name, email, details)
      # Find repo
      repo = Repository.find(repo_id)

      # Create client and check rate limit
      throw 'Rate limit reached' if (client = Octokit::Client.new access_token: repo.access_token).rate_limit.remaining < 10

      # Create the issue
      issue = create_issue(client, repo, repo.construct_body(sub_name, email, details))

      # Send notification email
      EmailWorker.perform_async NotificationMailer, :issue_submitted_email, repo.id, issue.number

      issue
    end

    private

    def add_orgs(orgs, user)
      # Record repo IDs that are found
      found_ids = []

      found_org_names = orgs.collect do |api_org|
        # Add the org
        org = add_org(api_org, user)

        # Add or create the org's repos
        found_ids += add_repos(api_org.rels[:repos].get.data, user, org)

        # Return its name
        org.name
      end

      # Remove user from any orgs they're no longer part of
      user.organizations.delete(Organization.where.not(name: found_org_names))

      # Return found IDs
      found_ids
    end

    def add_repos(repos, user, org = nil)
      owner = org || user

      repos.select(&:has_issues).collect do |api_repo|
        if (repo = owner.repositories.find_by_github_id(api_repo.id))
          # Update any information and ensure user is added
          repo.update(name: api_repo[:name], owner: api_repo[:owner][:login])
          repo.users << user

          # Add ID to return array
          api_repo.id.to_s
        # Else create it
        else
          Repository.create(github_id: api_repo[:id], name: api_repo[:name], is_active: false, organization: org, users: [user])
          nil
        end
      end.compact!
    end

    private

    def create_issue(client, repo, body)
      name = repo.holder_name + '/' + repo.name
      issue_name = repo.issue_name.present? ? repo.issue_name : 'Git Reports Issue'
      labels = { labels: repo.labels.present? ? repo.labels : '' }
      client.create_issue(name, issue_name, body, labels)
    end

    def add_org(api_org, user)
      org = Organization.find_or_create_by(name: api_org[:login])

      # Make sure it's added to the user
      org.users << user
      
      org
    end

    def retrieve_user(client, access_token)
      # Find
      user = User.find_or_create_by(access_token: access_token)
      user.update(username: client.user[:login], name: client.user[:name], avatar_url: client.user[:avatar_url])
      user
    end

    def remove_outdated(user, old_ids)
      old_ids.each do |github_id|
        # Delete user from repository
        (repo = Repository.find_by_github_id(github_id)).users.delete(user)

        # If the repo has no users left, disable it
        repo.update(is_active: false) if repo.users.count == 0
      end
    end
  end
end
