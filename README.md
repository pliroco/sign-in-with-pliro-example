# Example Sign in with Pliro integration

This repo contains an example integration demonstrating how to sign customers
into the website of a fictional newspaper called "The Greenfield Times", and
manage access to its content.

You can try the application live at [greenfieldtimes.news]. The site is using
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

To learn more about to build your integration, checkout the docs on [Sign in
with Pliro].

[Sign in with Pliro]: https://docs.pliro.co/custom-integrations/sign-in-with-pliro

## Running the app locally

To run this app locally you will need a Pliro test publication. If you don't
have one, email <calle@pliro.co> and I'll help you set one up!

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

You can then install Ruby and gem dependencies:

```sh
cd sign-in-with-pliro-example
rbenv install -s
gem install bundler
bundle install
```

The app will also need to be configured to connect with your Pliro publication.
[Create an OAuth application in the Pliro Dashboard] and copy the client ID and
secret into the following commands:

[Create an OAuth application in the Pliro Dashboard]: https://docs.pliro.co/custom-integrations/sign-in-with-pliro#prerequisites

```sh
echo 'PLIRO_PAGE_URL=https://your-publication.plirotest.page' >> .env.local
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
