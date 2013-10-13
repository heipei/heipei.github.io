task :default => :run

desc 'Build site with Jekyll'
task :build do
  jekyll("build")
end

desc 'Build site and start server with --auto'
task :run do
  jekyll 'serve --watch'
end

def jekyll(opts = '')
  sh 'rm -rf _site'
  sh 'jekyll ' + opts
end
