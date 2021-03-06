# plan = Forklift::Plan.new
# Or, you can pass configs
plan = Forklift::Plan.new ({
  # logger: {debug: true}
})

plan.do! {
  # do! is a wrapper around common setup methods (pidfile locking, setting up the logger, etc)
  # you don't need to use do! if you want finer control

  # cleanup from a previous run
  plan.step('Cleanup'){
    destination = plan.connections[:mysql][:destination]
    destination.exec("./transformations/cleanup.sql");
  end

  #  mySQL -> mySQL
  plan.step('Mysql Import'){
    source = plan.connections[:mysql][:source]
    destination = plan.connections[:mysql][:destination]
    source.tables.each do |table|
      Forklift::Patterns::Mysql.optimistic_pipe(source, table, destination, table)
      # will attempt to do an incremental pipe, will fall back to a full table copy
      # by default, incremental updates happen off of the `created_at` column, but you can modify this with "matcher"
    end
  }

  # Elasticsearch -> mySQL
  plan.step('Elasticsearch Import'){
    source = plan.connections[:elasticsearch][:source]
    destination = plan.connections[:mysql][:destination]
    table = 'es_import'
    index = 'aaa'
    query = { query: { match_all: {} } } # pagination will happen automatically
    destination.truncate!(table) if destination.tables.include? table
    source.read(index, query) {|data| destination.write(data, table) }
  }

  # mySQL -> Elasticsearch
  plan.step('Elasticsearch Load'){
    source = plan.connections[:mysql][:source]
    destination = plan.connections[:elasticsearch][:source]
    table = 'users'
    index = 'users'
    query = "select * from users" # pagination will happen automatically
    source.read(query) {|data| destination.write(data, table, true, 'user') }
  }

  # ... and you can write your own connections [LINK GOES HERE]

  # Do some SQL transformations
  plan.step('Transformations'){
    # SQL transformations are done exactly as they are written
    destination = plan.connections[:mysql][:destination]
    destination.exec!("./transformations/combined_name.sql")

    # Do some Ruby transformations
    # Ruby transformations expect `do!(connection, forklift)` to be defined
    destination = plan.connections[:mysql][:destination]
    destination.exec!("./transformations/email_suffix.rb")
  }

  # mySQL Dump the destination
  plan.step('Mysql Dump'){
    destination = plan.connections[:mysql][:destination]
    destination.dump('/tmp/destination.sql.gz')
  }

  # email the logs and a summary
  plan.step('Email'){
    destination = plan.connections[:mysql][:destination]

    email_args = {
      to:       "YOU@FAKE.com",
      from:     "Forklift",
      subject:  "value", "Forklift has moved your database @ #{Time.new}",
    }

    email_variables = {
      total_users_count:  destination.read('select count(1) as "count" from users')[0][:count],
      new_users_count:    destination.read('select count(1) as "count" from users where date(created_at) = date(NOW())')[0][:count],
    }

    email_template = "./template/email.erb"
    plan.mailer.send_template(email_args, email_template, email_variables, plan.logger.messages) unless ENV['EMAIL'] == 'false'
  }
}
