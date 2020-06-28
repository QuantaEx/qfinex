FROM ruby:2.6.5 as base

MAINTAINER developer@nexbit.io


ARG RAILS_ENV=production
ENV RAILS_ENV=${RAILS_ENV} APP_HOME=/home/app


ARG UID=1000
ARG GID=1000


ENV TZ=UTC


RUN groupadd -r --gid ${GID} app \
 && useradd --system --create-home --home ${APP_HOME} --shell /sbin/nologin --no-log-init \
      --gid ${GID} --uid ${UID} app


RUN apt-get update && apt-get upgrade -y
RUN apt-get install default-libmysqlclient-dev -y

WORKDIR $APP_HOME

COPY --chown=app:app Gemfile Gemfile.lock $APP_HOME/
RUN mkdir -p /opt/vendor/bundle \
 && chown -R app:app /opt/vendor $APP_HOME \
 && su app -s /bin/bash -c "bundle install --path /opt/vendor/bundle"


COPY --chown=app:app . $APP_HOME


USER app


RUN echo "# This file was overridden by default during docker image build." > Gemfile.plugin \
  && ./bin/init_config \
  && chmod +x ./bin/logger \
  && bundle exec rake tmp:create \
  && bundle exec rake assets:precompile


EXPOSE 3000

# The main command to run when the container starts.
CMD ["bundle", "exec", "puma", "--config", "config/puma.rb"]

# Extend base image with plugins.
FROM base

# Copy Gemfile.plugin for installing plugins.
COPY --chown=app:app Gemfile.plugin Gemfile.lock $APP_HOME/

# Install plugins.
RUN bundle install --path /opt/vendor/bundle
