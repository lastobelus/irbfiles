module GitContributors
  module String
    def obfuscate; gsub(/@/, " at the ").gsub(/\.(\w+)(>|$)/, ' dot \1s\2') end
    def htmlize; gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;") end
  end
    
  # @render_options :change_fields=>[:authors, :diffs]
  # @option :obfuscate, :type=>:boolean, :desc=>"Obfuscates emails"
  # @option :htmlize, :type=>:boolean, :desc=>"Render as html"
  # List git contributors by diff size using log
  def git_contributors(options={})
    ::String.send :include, String
    
    # Originally from http://git-wt-commit.rubyforge.org/git-rank-contributors
    #!/usr/bin/env ruby
    
    ## git-rank-contributors: a simple script to trace through the logs and
    ## rank contributors by the total size of the diffs they're responsible for.
    ## A change counts twice as much as a plain addition or deletion.
    ##
    ## Output may or may not be suitable for inclusion in a CREDITS file.
    ## Probably not without some editing, because people often commit from more
    ## than one address.
    ##
    ## git-rank-contributors Copyright 2008 William Morgan <wmorgan-git-wt-add@masanjin.net>. 
    ## This program is free software: you can redistribute it and/or modify
    ## it under the terms of the GNU General Public License as published by
    ## the Free Software Foundation, either version 3 of the License, or (at
    ## your option) any later version.
    ##
    ## This program is distributed in the hope that it will be useful,
    ## but WITHOUT ANY WARRANTY; without even the implied warranty of
    ## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    ## GNU General Public License for more details.
    ##
    ## You can find the GNU General Public License at:
    ##   http://www.gnu.org/licenses/
    
    lines = {}
    obfuscate = options[:obfuscate]
    htmlize = options[:htmlize]
    
    author = nil
    state = :pre_author
    `git log -M -C -C -p --no-color`.each do |l|
      case
      when (state == :pre_author || state == :post_author) && l =~ /Author: (.*)$/
        author = $1
        state = :post_author
        lines[author] ||= 0
      when state == :post_author && l =~ /^\+\+\+/
        state = :in_diff
      when state == :in_diff && l =~ /^[\+\-]/
        lines[author] += 1
      when state == :in_diff && l =~ /^commit /
        state = :pre_author
      end
    end
    
    lines.sort_by { |a, c| -c }.map do |a, c|
      a = a.obfuscate if obfuscate
      a = a.htmlize if htmlize
      [a,c]
    end
  
  end
end
