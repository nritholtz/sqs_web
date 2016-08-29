sqs_web
===============
[![Build Status](https://travis-ci.org/nritholtz/sqs_web.svg?branch=master)](https://travis-ci.org/nritholtz/sqs_web)
[![Code Climate](https://codeclimate.com/github/nritholtz/sqs_web/badges/gpa.svg)](https://codeclimate.com/github/nritholtz/sqs_web)
[![Test Coverage](https://codeclimate.com/github/nritholtz/sqs_web/badges/coverage.svg)](https://codeclimate.com/github/nritholtz/sqs_web/coverage)

A [delayed_job_web](https://github.com/ejschmitt/delayed_job_web) inspired (read: stolen) interface for SQS.
This gem was written to work anchored within rails 3 and 4 applications.

Some features:

* Easily view messages visible and in-flight in your configured SQS queues
* Move any single enqueued message, or all enqueued messages, from a DLQ to the corresponding active queue
* Remove an enqueued message, or easily remove all enqueued messages from a DLQ
* View overview stats for the queues

The interface:

![Screen shot](https://www.dropbox.com/s/j14s0aqthj8w3d2/sqs_web_dashboard.png?dl=1)


Quick Start For Rails 3 and 4 Applications
------------------------------------

Add the dependency to your Gemfile

```ruby
gem "sqs_web"
```

Install it...

```ruby
bundle
```

Add the following route to your application for accessing the interface,
and actions related to the messages.

```ruby
match "/sqs" => SqsWeb, :anchor => false, via: [:get, :post]
```

You probably want to password protect the interface, an easy way is to add something like this your config.ru file

```ruby
if Rails.env.production?
  SqsWeb.use Rack::Auth::Basic do |username, password|
    username == 'username' && password == 'password'
  end
end
```

`sqs_web` runs as a Sinatra application within the rails application. Visit it at `/sqs`.

## Supported SqsWeb configuration options
The ```aws``` section is used to configure the Aws objects used by sqs_web internally. The sqs_web-specific keys are listed below, and you can expect any other key defined in that block to be passed on untouched to ```Aws::SQS::Client#initialize```:

- `access_key_id` : AWS Access Key. If not set will default to environment variable `AWS_ACCESS_KEY_ID` or instance profile credentials
- `secret_access_key` : AWS Secret Access Key. If not set will default to environment variable `AWS_SECRET_ACCESS_KEY` or instance profile credentials.
- `region`: AWS region for the SQS queue. If not set will default to environment variable `AWS_REGION` or else to `us-east-1`.
- `sqs_endpoint` can be used to explicitly override the SQS endpoint. If not set will default to environment variable `AWS_SQS_ENDPOINT` or default SQS endpoint.

`SqsWeb.options[:queues]` supports an array of strings for the SQS queue names.
```ruby
SqsWeb.options[:queues] =  ["TestSourceQueue", "TestSourceQueueDLQ"]
```

## Notes
Currently, this was written in mind for being only used for DLQ management. The [AWS SQS Management Console](https://aws.amazon.com/blogs/aws/aws-management-console-now-supports-the-simple-queue-service-sqs/) should have most of the functionality that you would want out of the box, this plugin is **not meant as a replacement for the AWS SQS Management Console**, but rather as a supplement. There are some features that are not implemented yet (e.g. moving a message from a DLQ back to the source queue) in the AWS Console, and there are some additional benefits for the management screen to live within the application.

This is not to say there are some features that may be duplicated or added to this plugin as it advances. In addition, our internal applications are using [Shoryuken](https://github.com/phstc/shoryuken) which uses `message attributes` (e.g. *ApproximateReceiveCount*) that become "invalid" once you pick up the message from an active queue. There is greater freedom when managing a DLQ, since this plugin is assuming that the management console (or the AWS SQS Management Console) are the only consumers of the DLQ, which solves the complexity of these `message attributes`.

## Serving static assets

If you mount the app on another route, you may encounter the CSS not working anymore. To work around this you can leverage a special HTTP header. Install it, activate it and configure it -- see below.

### Apache

    XSendFile On
    XSendFilePath /path/to/shared/bundle

[`XSendFilePath`](https://tn123.org/mod_xsendfile/) white-lists a directory from which static files are allowed to be served. This should be at least the path to where delayed_job_web is installed.

Using Rails you'll have to set `config.action_dispatch.x_sendfile_header = "X-Sendfile"`.

### Nginx

Nginx uses an equivalent that's called `X-Accel-Redirect`, further instructions can be found [in their wiki](http://wiki.nginx.org/XSendfile).

Rails' will need to be configured to `config.action_dispatch.x_sendfile_header = "X-Accel-Redirect"`.

### Lighttpd

Lighty is more `X-Sendfile`, like [outlined](http://redmine.lighttpd.net/projects/1/wiki/X-LIGHTTPD-send-file) in their wiki.


Contributing
------------

* To bootstrap a `fake_sqs` environment for development purposes, run the following:
```ruby
bundle exec ruby scripts/bootstrap_queues.rb
```

1. Fork
2. Hack
3. `rake test`
4. Send a pull request


Releasing a new version
-----------------------

1. Update the version in `sqs_web.gemspec`
2. `git commit sqs_web.gemspec` with the following message format:

        Version x.x.x

        Changelog:
        * Some new feature
        * Some new bug fix
3. `rake release`