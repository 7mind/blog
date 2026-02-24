
```bash
# one-time
direnv allow

# local test server
bundle install
bundle exec jekyll serve --livereload --incremental

# production-like build verification
JEKYLL_ENV=production bundle exec jekyll build
```
