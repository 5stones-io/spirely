max_threads_count = ENV.fetch("RAILS_MAX_THREADS", 5)
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
threads min_threads_count, max_threads_count

bind "tcp://0.0.0.0:#{ENV.fetch('PORT', 3000)}"

environment ENV.fetch("RAILS_ENV", "development")

workers ENV.fetch("WEB_CONCURRENCY", 0)
preload_app! if ENV.fetch("WEB_CONCURRENCY", "0").to_i > 0
