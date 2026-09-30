# Creating the HR account is an operator action, never an API call: there is no
# registration endpoint (config/routes.rb), so this table can only be written by
# somebody with console, rake or database access.
#
#   bin/rails auth:create_hr_user HR_EMAIL=hr@example.com HR_PASSWORD=...
#
# Credentials are read from the environment and are never echoed, stored in the
# repository or written to the log. Re-running the task updates the password of
# an existing account rather than creating a duplicate, which is what makes it
# safe to use for rotating a password.
namespace :auth do
  desc "Create or update the HR account from HR_EMAIL and HR_PASSWORD"
  task create_hr_user: :environment do
    email = ENV["HR_EMAIL"].to_s.strip
    password = ENV["HR_PASSWORD"].to_s

    if email.blank? || password.blank?
      abort "Both HR_EMAIL and HR_PASSWORD must be set. " \
            "The password is not echoed here on purpose; pass it via the environment."
    end

    user = User.find_or_initialize_by(email: email.downcase)
    created = user.new_record?

    user.password = password
    user.password_confirmation = password

    unless user.save
      abort "Could not save the HR account: #{user.errors.full_messages.to_sentence}"
    end

    # Only the address is reported. Nothing about the password is printed.
    puts "#{created ? 'Created' : 'Updated'} the HR account #{user.email}."
  end
end
