# oidc-example

This repo contains an example implementation of signing in customers with Pliro
and managing access to the content of a fictional newspaper called **The
Greenfield Times**.

You can try this application live at [greenfieldtimes.news]. The site is using
Pliro's test environment which allows you to create a subscription without
incurring any costs.

[greenfieldtimes.news]: https://www.greenfieldtimes.news

The application is built in [Ruby] using the minimal [Sinatra] web framework
(similar to [Express], [Flask], etc.) but we hope that the code will look
familiar to developers using other programming languages and frameworks too.

[Ruby]: https://www.ruby-lang.org
[Sinatra]: https://sinatrarb.com
[Express]: https://expressjs.com
[Flask]: https://flask.palletsprojects.com

## Running the app locally

To run this app locally you will need a Pliro test account. If you don't have
one, email <calle@pliro.co> and I'll help you set one up!

This app also requires [Ruby], [Bundler], and [Redis] to run. We recommend using
[rbenv] (or similar) to install Ruby. On macOS you can install rbenv and Redis
using Homebrew:

[Bundler]: https://bundler.io
[Redis]: https://redis.io
[rbenv]: https://github.com/rbenv/rbenv

```sh
brew install rbenv ruby-build redis
brew services start redis
```

To set up rbenv, run this and follow the printed instructions:

``` sh
rbenv init
```

You can then install Ruby with rbenv, and Bundler with gem:

```sh
cd oidc-example
rbenv install -s
gem install bundler
```

Then, use Bundler to install the other Ruby gems this app depends on:

```sh
bundle install
```

The app will also need some configuration to connect with your Pliro account.
Create an OAuth application in the Pliro Dashboard and copy the client ID and
client secret into the following commands:

```sh
echo 'PLIRO_PAGE_URL=https://your-account.plirotest.page' >> .env.local
echo 'PLIRO_ISSUER=https://your-account.plirotest.page' >> .env.local
echo 'PLIRO_CLIENT_ID=your-client-id' >> .env.local
echo 'PLIRO_CLIENT_SECRET=your-client-secret' >> .env.local
```

You should now be ready to start the server:

```sh
ruby server.rb
```

Now visit <http://localhost:4567> in your browser! 🎉

## Support

Feel free to reach out to <calle@pliro.co> if you run into any issues.
