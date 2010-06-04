module RdfLib
  def self.included(mod)
    require 'rdf'
  end

  # @render_options :change_fields=>[:subject, :predicate, :object]
  # @options :format=>''
  # Parse and display an rdf file in a variety of formats
  def dump_rdf(uri, options={})
    require 'rdf/ntriples' if uri[/\.nt$/]
    require 'rdf/json' if uri[/\.json$/]
    require 'rdf/raptor' if uri[/\.(rdf|ttl)$/] || options[:format][/rdf|ttl/]
    RDF::Graph.load(uri).data.map {|e| e.to_a }
  end

  ENDPOINTS = {'bio'=>'http://hcls.deri.org/sparql', 'space'=>'http://api.talis.com/stores/space/services/sparql'}

  # @options :type=>{:default=>'classes', :values=>%w{classes objects show_object properties} },
  #   :endpoint=>{:values=> ENDPOINTS.keys, :default=>'http://api.talis.com/stores/space/services/sparql'},
  #   :limit=>:numeric, :offset=>:numeric, :abbreviate=>:boolean
  # Query and explore a sparql endpoint
  def sparql(*args)
    options = args[-1].is_a?(Hash) ? args.pop : {}
    options[:endpoint] = ENDPOINTS[options[:endpoint]] || options[:endpoint]
    require 'sparql/client'
    client = SPARQL::Client.new(options[:endpoint])
    if options[:sparql]
      # %[SELECT DISTINCT ?x { [] a ?x }]
      solutions = client.query(args.join(' '))
    else
      query = case options[:type]
      when 'classes'
        client.select(:o).where([:s,RDF.type,:o]).distinct
      when 'objects'
        # http://purl.org/net/schemas/space/LaunchSite
        args[0] ?  client.select(:s).where([:s, RDF.type, RDF::URI.new(args[0])]).distinct :
          client.select(:s).where([:s, :p, :o]).distinct
      when 'properties'
        client.select(:p).where([:s, :p, :o]).distinct
      when 'show_object'
        # http://nasa.dataincubator.org/launchsite/capecanaveral
        client.select(:p, :o).where([RDF::URI.new(args[0]), :p, :o])
      when 'graphs'
        #select distinct ?Concept ?g where {
          #GRAPH ?g { [] a ?Concept }
        #}
      end
      query.limit(options[:limit]) if options[:limit]
      query.offset(options[:offset]) if options[:offset]
      solutions = query.solutions
    end
    results = solutions && solutions.map {|e| e.to_hash }
    abbreviate_uris(results) if options[:abbreviate]
    results
  end

  NAMESPACES = {
    'foaf'=>'http://xmlns.com/foaf/0.1/',
    'dc'=>'http://purl.org/dc/terms/',
    'geo'=>'http://www.w3.org/2003/01/geo/wgs84_pos#',
    'rdfs'=>'http://www.w3.org/2000/01/rdf-schema#',
    'owl'=>'http://www.w3.org/2002/07/owl#',
    'rdf'=>'http://www.w3.org/1999/02/22-rdf-syntax-ns#',
    'dbp'=>'http://dbpedia.org/property/',
    'skos'=>'http://www.w3.org/2004/02/skos/core#',
    'xsd'=>'http://www.w3.org/2001/XMLSchema#',
    'sioc'=>'http://rdfs.org/sioc/ns#',
    'po'=>'http://purl.org/ontology/po/',
  }
  def abbreviate_uris(arr)
    arr.each {|e|
      e.each {|k,v|
        if (match = NAMESPACES.find {|abbr,uri| v.to_s[/^#{uri}/] })
          e[k] = v.to_s.sub(/^#{match[1]}/,match[0]+":")
        end
      }
    }
  end
end
