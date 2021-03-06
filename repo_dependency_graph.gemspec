$LOAD_PATH.unshift File.expand_path("../lib", __FILE__)
name = "repo_dependency_graph"
require "#{name.gsub("-","/")}/version"

Gem::Specification.new name, RepoDependencyGraph::VERSION do |s|
  s.summary = "Show the dependencies of your private repos"
  s.authors = ["Michael Grosser"]
  s.email = "michael@grosser.it"
  s.homepage = "http://github.com/grosser/#{name}"
  s.files = `git ls-files lib/ bin/`.split("\n")
  s.license = "MIT"
  s.executables = ["repo-dependency-graph"]
  s.add_runtime_dependency "organization_audit"
  cert = File.expand_path("~/.ssh/gem-private-key-grosser.pem")
  if File.exist?(cert)
    s.signing_key = cert
    s.cert_chain = ["gem-public_cert.pem"]
  end
end
