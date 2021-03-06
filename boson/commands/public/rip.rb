# Commands to enhance rip2
module RipLib
  def self.included(mod)
    require 'rip'
  end

  # @options :local=>:boolean, :env=>{:type=>:string, :values=>%w{test db rdf base irb misc web},
  #  :enum=>false }, :version=>:string, :debug=>:boolean, :force=>:boolean
  # @config :alias=>'rip'
  # Enhance rip install
  def rip_install(*args)
    options = args[-1].is_a?(Hash) ? args.pop : {}
    args = [ "file://"+File.expand_path('.') ] if options[:local]
    ENV['RIPENV'] = options[:env] if options[:env]
    args.each {|e|
      sargs = ['rip','install', e]
      sargs << options[:version] if options[:version]
      sargs.insert(2, '-d') if options[:debug]
      sargs.insert(2, '-f') if options[:force]
      system *sargs
    }
  end

  # @options :status=>:boolean, :version=>:boolean, :dir=>:boolean, :env=>:string, :active=>:boolean
  # @config :alias=>'rl'
  # List rip packages
  def rip_list(options={})
    setup_helpers

    active = ENV['RUBYLIB'].to_s.split(":")
    envs = Rip.envs
    envs = envs.select {|e| e[options[:env]] } if options[:env]
    envs = ['active'] if options[:active]
    envs.inject([]) {|t,e|
      ENV['RIPENV'] = e
      env = options[:status] ? rip_env_status(e, active)+e : e
      if options[:version] || options[:dir]
        Rip::Helpers.rip(:installed).each {|dir|
          pkg = Rip::Helpers.metadata(dir)
          hash = {:env=>env, :package=>pkg.name, :version=>pkg.version}
          t << (options[:dir] ? hash.merge(:dir=>dir.chomp) : hash)
        }
        t
      else
        t << {:env=>env, :packages=>current_packages}
      end
    }
  end

  # @options :local=>:boolean, :env=>{:type=>:string, :values=>%w{test db rdf base irb misc web},
  #  :enum=>false }, :recursive=>:boolean, :pretend=>:boolean, :safe=>:boolean
  # Wrapper around rip uninstall
  def rip_uninstall(*args)
    options = args[-1].is_a?(Hash) ? args.pop : {}
    args += package_recursive_deps(args[0], :array=>true, :uninstall=>true) if options[:recursive]
    if options[:recursive] && options[:safe]
      reverse_deps = all_deps(:reverse=>true)
      args, weeds = args.partition {|e|
        (reverse_deps[e] || []).size <= 1
      }
      puts "These packages are dependencies for other packages: #{weeds.join(', ')}"
    end
    return args if options[:pretend]
    ENV['RIPENV'] = options[:env] if options[:env]
    if options[:recursive] && find_package(args[0])
      options[:env] = ENV['RIPENV']
    end
    args.each {|e|
      find_package(e) unless options[:env]
      system 'rip','uninstall', e
    }
  end

  # @options :dir=>:boolean, :strict=>:boolean, :exceptions=>:boolean
  # Prints dirty files in lib/ of rip envs i.e. ones that don't match any package namespace
  def rip_dirty_lib(options={})
    list = rip_list
    list.map {|hash|
      lib_dir = ENV['RIPDIR']+"/#{hash[:env]}/lib/"
      env_files = Dir.glob(lib_dir+"*").map {|e| File.basename(e) }
      filter = options[:strict] ? '^%s(\.\w+$|$)' : '^%s'
      env_files = env_files.reject {|f|
        hash[:packages].any? {|e|
          namespace = e[/\w+/]
          f[Regexp.new(filter % namespace)] ||
            (options[:exceptions] ? dirty_lib_exception(f, e) : false)
        }
      }
      if options[:dir]
        env_files.map! {|e| File.directory?(lib_dir+e) ?
          (e+"("+Dir.glob(lib_dir+e+"/**/*.*").size.to_s+")") : e
        }
      end
      [hash[:env], env_files]
    }
  end

  # Prints top level files which should be symlinks
  def dirty_links
    Dir.glob(File.expand_path("~/.rip/*/{lib,bin}/*")).select {|e| !File.symlink?(e) }
  end

  # @options :delete=>:boolean, :non_standard=>:boolean
  # Checks for broken or nonstandard symlinks
  def rip_symlinks(*files)
    options = files[-1].is_a?(Hash) ? files.pop : {}
    files = files.empty? ?  Dir.glob([File.expand_path("~/.rip/*/**/*.{rb,?}"), File.expand_path("~/.rip/*/bin/*")]) :
      files.map {|e| File.directory?(e) ? Dir.glob(e+'/**/*') : e }.flatten
    symlinks = files.select {|e| File.symlink?(e) }.map {|e| [e, File.readlink(e)] }
    puts "Checking #{symlinks.size} symlinks"
    symlinks = if options[:non_standard]
      package_dir = File.expand_path("~/.rip/.packages")
      symlinks.reject {|k,v| v[/^#{package_dir}/] }
    else
      symlinks.select {|k,v| !File.exists?(v) }
    end
    menu(symlinks).each {|k,v| File.unlink(k) } if options[:delete]
    symlinks
  end

  # @options :verbose=>:boolean
  # Verifies that packages in envs load. Returns ones that fail with LoadError
  def rip_verify(*envs)
    options = envs[-1].is_a?(Hash) ? envs.pop : {}
    envs = Rip.envs if envs.empty?
    failed = {}
    exceptions = %w{mynyml ssoroka matthew ruby-}
    envs.each {|e|
      ENV['RIPENV'] = e
      ENV['RUBYLIB'] += ":#{ENV['RIPDIR']}/#{e}/lib"
      puts "Verifying env #{e}"
      current_packages.each {|f|
        begin
          require 'rdf' if f[/rdf/]
          f2 = f[Regexp.union(*exceptions)] ? f.sub(/^\w+-/, '') : f.sub('-', '/')
          puts "Requiring '#{f2}'" if options[:verbose]
          require f2
        rescue LoadError
          (failed[e] ||= []) << f
        end
      }
    }
    failed
  end

  # Runs `rake test in rip package directory across any env
  def rip_test(pkg)
    if (dir = find_package(pkg))
      Dir.chdir dir
      exec 'rake', 'test'
    end
  end

  # Execute a git command on a package
  def rip_git(pkg, *args)
    if (dir = find_package(pkg))
      Dir.chdir dir
      exec 'git', *args
    end
  end

  # Get rip-info across any env
  def rip_info(*args)
    find_package(args[0]) && exec('rip','info', *args)
  end

  # rip-readme across any env
  def rip_readme(pkg)
    find_package(pkg) && exec('rip','readme', pkg)
  end

  # @options :file=>{:default=>'gemspec', :values=>%w{gemspec changelog rakefile version}, :enum=>false}
  # Displays top level file from a rip package
  def rip_file(pkg, options={})
    globs = {'gemspec'=>'{gemspec,*.gemspec}', 'changelog'=>'{CHANGELOG,HISTORY}'}
    file_glob = globs[options[:file]] || options[:file]
    (dir = find_package(pkg)) && (file = Dir.glob("#{dir}/*#{file_glob}*", File::FNM_CASEFOLD)[0]) &&
      File.file?(file) ? File.read(file) : "No file '#{options[:file]}'"
  end

  # @options :verbose=>:boolean, :recursive=>true, :uninstall=>:boolean
  # Prints dependencies for package in any env
  def rip_deps(pkg, options={})
    return package_deps(pkg) if !options[:recursive]
    nodes = package_recursive_deps(pkg, options)
    render nodes, :class=>:tree, :type=>:directory
  end

  # @options :reverse=>:boolean
  # Lists all deps in env
  def all_deps(options={})
    packages = rip_list(:active=>true, :dir=>true)
    package_dirs = packages.map {|e| e[:dir] }
    deps = packages.inject({}) {|t,e| t[e[:package]] = package_deps(e[:package], package_dirs).map {|e| e[/\S+/]}; t }
    return deps if !options[:reverse]
    deps.invert.inject({}) {|t,(k,v)|
      k.each {|e| (t[e] ||=[]) << v }
      t
    }
  end

  # Finds rip package and returns package directory name
  def find_package(pkg)
    setup_helpers

    Rip.envs.each {|env|
      ENV['RIPENV'] = env
      Rip::Helpers.rip(:installed).each {|curr|
        return curr.chomp if curr[/\/#{pkg}-\w{32}/]
      }
    }
    nil
  end

  private
  def dirty_lib_exception(path, namespace)
    exceptions = %w{rubygems rubygems_plugin.rb autotest tasks}
    namespace_exceptions = {'rdf'=>'^df', 'rspec'=>'^spec', 'json_pure'=>'^json', 'ssoroka-ansi'=>'^ansi', 'googlebase'=>'google',
      'activesupport'=>'active_support', 'mynyml-every'=>'every', 'ruby-gmail'=>'gmail', 'matthew-method_lister'=>'method_lister',
      'git-hub'=>'hub'}
    exceptions.include?(path) || ((exc = namespace_exceptions[namespace]) && path[/#{exc}/])
  end

  def setup_helpers
    @setup_helpers ||= begin
      require 'rip/helpers'
      Rip::Helpers.extend Rip::Helpers
      true
    end
  end

  def current_packages
    setup_helpers
    Rip::Helpers.rip(:installed).map {|dir| dir[/\/([^\/]+)-\w{32}/, 1] }
  end

  def all_packages
    @packages ||= rip_list(:dir=>true).map {|e| e[:dir] }
  end

  def package_recursive_deps(pkg, options={})
    @nodes, @options = [], options
    build_recursive_deps(pkg, 0)
    if options[:uninstall]
      @nodes.each {|e| e[:value] = uninstall_to_install(e[:value]) }
    end
    options[:array] ? @nodes.map {|e| e[:value] } - [pkg] : @nodes
  end

  def uninstall_to_install(pkg)
    pkg[/^git:.*?([^\/]+)\.git/, 1] || pkg[/\/([^\/]+)$/, 1] || pkg[/\S+/]
  end

  def build_recursive_deps(pkg, index)
    p [pkg, index] if @options[:verbose]
    @nodes << {:level=>index, :value=>pkg}
    package_deps(pkg[/\w+/]).each {|e|
      build_recursive_deps(e, index + 1)
    }
  end

  def package_deps(pkg, packages=all_packages)
    (pkg_dir = packages.find {|e| e[/\/#{pkg}-\w{32}/] }) ?
      (File.read("#{pkg_dir}/deps.rip").split("\n") rescue []) : []
  end

  def rip_env_status(env, active_envs)
    env == Rip.env ? "* " :
      active_envs.any? {|e| e == "#{ENV['RIPDIR']}/#{env}/lib" } ?  "+ " : "  "
  end
end
