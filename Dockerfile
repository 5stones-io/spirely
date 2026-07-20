FROM ruby:3.3-slim

RUN apt-get update -qq && apt-get install -y \
    build-essential \
    libpq-dev \
    libyaml-dev \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock spirely.gemspec ./
COPY lib/spirely/version.rb lib/spirely/version.rb
RUN bundle install

COPY . .

EXPOSE 3000

CMD ["sh", "-c", "bundle exec rails db:migrate && bundle exec puma -C config/puma.rb"]
