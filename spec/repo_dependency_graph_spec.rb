require "spec_helper"

describe RepoDependencyGraph do
  let(:config){ YAML.load_file("spec/private.yml") }

  it "has a VERSION" do
    RepoDependencyGraph::VERSION.should =~ /^[\.\da-z]+$/
  end

  context ".dependencies" do
    before do
      RepoDependencyGraph.stub(:puts)
    end

    if File.exist?("spec/private.yml")
      it "gathers dependencies for private organizations" do
        graph = RepoDependencyGraph.send(:dependencies,
          :organization => config["organization"],
          :token => config["token"],
          :select => Regexp.new(config["expected_organization_select"])
        )
        expected = graph[config["expected_organization"]]
        expected.should == config["expected_organization_dependencies"]
      end
    end

    it "gathers dependencies for a user" do
      graph = RepoDependencyGraph.send(:dependencies, :user => "repo-test-user")
      graph.should == {"repo_a"=>["repo_b", "repo_c"], "repo_c"=>["repo_b"]}
    end

    it "finds nothing for private when all repos are public" do
      graph = RepoDependencyGraph.send(:dependencies, :user => "repo-test-user", :private => true)
      graph.should == {}
    end

    it "can filter" do
      graph = RepoDependencyGraph.send(:dependencies, :user => "repo-test-user", :select => /_b|a/)
      graph.should == {"repo_a"=>["repo_b"]}
    end

    it "can reject" do
      graph = RepoDependencyGraph.send(:dependencies, :user => "repo-test-user", :reject => /_c/)
      graph.should == {"repo_a"=>["repo_b"]}
    end

    it "gathers chef dependencies for a user" do
      graph = RepoDependencyGraph.send(:dependencies, :user => "repo-test-user", :chef => true)
      graph.should == {"chef_a"=>["chef_b", "chef_c"], "chef_c"=>["chef_b"]}
    end

    it "can include external dependencies" do
      graph = RepoDependencyGraph.send(:dependencies, :user => "repo-test-user", :external => true)
      graph.should == {"repo_a"=>["repo_b", "repo_c"], "repo_c"=>["repo_b", "activesupport"]}
    end

    it "can map repo names so misnamed repos can be found as internal" do
      graph = RepoDependencyGraph.send(:dependencies, :user => "repo-test-user", :map => [/repo_(c|d)/, "activesupport"])
      graph.should == {"repo_a"=>["repo_b"], "repo_c"=>["repo_b", "activesupport"]}
    end

    it "can map repo names to nothing" do
      graph = RepoDependencyGraph.send(:dependencies, :user => "repo-test-user", :map => [/repo_/])
      graph.should == {}
    end

    it "prevents silly map and external" do
      expect {
        RepoDependencyGraph.send(:dependencies, :user => "repo-test-user", :map => [/repo_(c|d)/, "activesupport"], :external => true)
      }.to raise_error(/internal/)
    end
  end

  context ".draw" do
    it "draws" do
      Dir.mktmpdir do
        Dir.chdir do
          RepoDependencyGraph.send(:draw, "foo" => ["bar"])
          File.exist?("out.png").should == true
        end
      end
    end
  end

  context ".color" do
    it "calculates for 1 to max" do
      values = [1,2,25,50,51]
      values.map do |k,v|
        [k, RepoDependencyGraph.send(:color, k, values.min..values.max)]
      end.should == [[1, "#80f31f"], [2, "#89ef19"], [25, "#fd363f"], [50, "#492efa"], [51, "#3f36fd"]]
    end
  end

  context ".load_spec" do
    it "loads simple spec" do
      spec = RepoDependencyGraph.send(:load_spec, <<-RUBY)
        Gem::Specification.new "foo" do |s|
          s.add_runtime_dependency "xxx", "1.1.1"
        end
      RUBY
      spec.name.should == "foo"
    end

    it "loads spec with require" do
      spec = RepoDependencyGraph.send(:load_spec, <<-RUBY)
        require 'asdadadsadas'
        Gem::Specification.new "foo" do |s|
          s.add_runtime_dependency "xxx", "1.1.1"
        end
      RUBY
      spec.name.should == "foo"
    end

    it "loads spec with VERSION" do
      spec = RepoDependencyGraph.send(:load_spec, <<-RUBY)
        Gem::Specification.new "foo", Foo::VERSION do |s|
          s.add_runtime_dependency "xxx", "1.1.1"
        end
      RUBY
      spec.name.should == "foo"
      spec.version.to_s.should == "1.2.3"
    end

    it "loads spec with VERSION::STRING" do
      spec = RepoDependencyGraph.send(:load_spec, <<-RUBY)
        Gem::Specification.new "foo", Foo::VERSION::STRING do |s|
          s.add_runtime_dependency "xxx", "1.1.1"
        end
      RUBY
      spec.name.should == "foo"
      spec.version.to_s.should == "1.2.3"
    end

    it "leaves Gem::Version alone" do
      spec = RepoDependencyGraph.send(:load_spec, <<-RUBY)
        Gem::Version.new("1.1.1") || Gem::VERSION
        Gem::Specification.new "foo", Foo::VERSION::STRING do |s|
          s.add_runtime_dependency "xxx", "1.1.1"
        end
      RUBY
      spec.name.should == "foo"
      spec.version.to_s.should == "1.2.3"
    end

    it "does not modify $LOAD_PATH" do
      expect {
        RepoDependencyGraph.send(:load_spec, <<-RUBY)
          $LOAD_PATH << "xxx"
          $:.unshift "xxx"
          Gem::Specification.new "foo", Foo::VERSION do |s|
            s.add_runtime_dependency "xxx", "1.1.1"
          end
        RUBY
      }.to_not change { $LOAD_PATH }
    end

    it "loads spec with File.read" do
      spec = RepoDependencyGraph.send(:load_spec, <<-RUBY)
        Gem::Specification.new "foo", File.read("VERSION") do |s|
          s.add_runtime_dependency "xxx", "1.1.1"
        end
      RUBY
      spec.name.should == "foo"
      spec.version.to_s.should == "1.2.3"
    end

    it "loads spec with File.read from unknown file (travis-ci)" do
      spec = RepoDependencyGraph.send(:load_spec, <<-RUBY)
        File.read(foooo) =~ /\\bVERSION\\s*=\\s*["'](.+?)["']/
        version = \$1
        Gem::Specification.new "foo", version do |s|
          s.add_runtime_dependency "xxx", "1.1.1"
        end
      RUBY
      spec.name.should == "foo"
      spec.version.to_s.should == "1.2.3"
    end

    it "loads spec with IO.read" do
      spec = RepoDependencyGraph.send(:load_spec, <<-RUBY)
        Gem::Specification.new "foo", IO.read("VERSION") do |s|
          s.add_runtime_dependency "xxx", "1.1.1"
        end
      RUBY
      spec.name.should == "foo"
      spec.version.to_s.should == "1.2.3"
    end

    it "returns nil on error" do
      RepoDependencyGraph.send(:load_spec, "raise").should == nil
    end
  end

  context ".parse_options" do
    def call(argv, keep_defaults=false)
      result = RepoDependencyGraph.send(:parse_options, argv)
      result.delete(:user) unless keep_defaults
      result
    end

    it "uses current user by default" do
      result = call([], true)
      result.keys.should == [:user]
    end

    it "parses --user" do
      call(["--user", "foo"], true).should == {:user => "foo"}
    end

    it "parses --organization" do
      call(["--organization", "foo"]).should == {:organization => "foo"}
    end

    it "parses --token" do
      call(["--token", "foo"]).should == {:token => "foo"}
    end

    it "parses --private" do
      call(["--private"]).should == {:private => true}
    end

    it "parses --external" do
      call(["--external"]).should == {:external => true}
    end

    it "parses --chef" do
      call(["--chef"]).should == {:chef => true}
    end

    it "parses simple --map" do
      call(["--map", "A=B"]).should == {:map => [/A/, "B"]}
    end

    it "parses empty --map" do
      call(["--map", "A="]).should == {:map => [/A/, ""]}
    end

    it "parses regex --map" do
      call(["--map", "A.?=B"]).should == {:map => [/A.?/, "B"]}
    end

    it "parses --select" do
      call(["--select", "A.?B"]).should == {:select => /A.?B/}
    end

    it "parses --reject" do
      call(["--reject", "A.?B"]).should == {:reject => /A.?B/}
    end
  end

  context "CLI" do
    it "shows --version" do
      audit("--version").should include(RepoDependencyGraph::VERSION)
    end

    it "shows --help" do
      audit("--help").should include("Draw repo dependency graph from your organization")
    end

    def audit(command, options={})
      sh("bin/repo-dependency-graph #{command}", options)
    end

    def sh(command, options={})
      result = `#{command} #{"2>&1" unless options[:keep_output]}`
      raise "FAILED #{command}\n#{result}" if $?.success? == !!options[:fail]
      result
    end
  end
end
