require 'open-uri'
require 'json/ld/expand'
require 'json/ld/compact'
require 'json/ld/flatten'
require 'json/ld/frame'
require 'json/ld/to_rdf'
require 'json/ld/from_rdf'

module JSON::LD
  ##
  # A JSON-LD processor based on the JsonLdProcessor interface.
  #
  # This API provides a clean mechanism that enables developers to convert JSON-LD data into a a variety of output formats that are easier to work with in various programming languages. If a JSON-LD API is provided in a programming environment, the entirety of the following API must be implemented.
  #
  # Note that the API method signatures are somewhat different than what is specified, as the use of Futures and explicit callback parameters is not as relevant for Ruby-based interfaces.
  #
  # @see http://json-ld.org/spec/latest/json-ld-api/#the-application-programming-interface
  # @author [Gregg Kellogg](http://greggkellogg.net/)
  class API
    include Expand
    include Compact
    include ToRDF
    include Flatten
    include FromRDF
    include Frame

    # Options used for open_file
    OPEN_OPTS = {
      :headers => {"Accept" => "application/ld+json, application/json"}
    }

    # Current input
    # @!attribute [rw] input
    # @return [String, #read, Hash, Array]
    attr_accessor :value

    # Input evaluation context
    # @!attribute [rw] context
    # @return [JSON::LD::Context]
    attr_accessor :context

    # Current Blank Node Namer
    # @!attribute [r] namer
    # @return [JSON::LD::BlankNodeNamer]
    attr_reader :namer

    ##
    # Initialize the API, reading in any document and setting global options
    #
    # @param [String, #read, Hash, Array] input
    # @param [String, #read,, Hash, Array, JSON::LD::Context] context
    #   An external context to use additionally to the context embedded in input when expanding the input.
    # @param  [Hash{Symbol => Object}] options
    # @option options [Boolean] :base
    #   The Base IRI to use when expanding the document. This overrides the value of `input` if it is a _IRI_. If not specified and `input` is not an _IRI_, the base IRI defaults to the current document IRI if in a browser context, or the empty string if there is no document context.
    # @option options [Boolean] :compactArrays (true)
    #   If set to `true`, the JSON-LD processor replaces arrays with just one element with that element during compaction. If set to `false`, all arrays will remain arrays even if they have just one element.
    # @option options [Boolean, String, RDF::URI] :flatten
    #   If set to a value that is not `false`, the JSON-LD processor must modify the output of the Compaction Algorithm or the Expansion Algorithm by coalescing all properties associated with each subject via the Flattening Algorithm. The value of `flatten must` be either an _IRI_ value representing the name of the graph to flatten, or `true`. If the value is `true`, then the first graph encountered in the input document is selected and flattened.
    # @option options [Boolean] :optimize (false)
    #   If set to `true`, the JSON-LD processor is allowed to optimize the output of the Compaction Algorithm to produce even compacter representations. The algorithm for compaction optimization is beyond the scope of this specification and thus not defined. Consequently, different implementations *MAY* implement different optimization algorithms.
    #   (Presently, this is a noop).
    # @option options [Boolean] :useNativeTypes (true)
    #   If set to `true`, the JSON-LD processor will use native datatypes for expression xsd:integer, xsd:boolean, and xsd:double values, otherwise, it will use the expanded form.
    # @option options [Boolean] :useRdfType (false)
    #   If set to `true`, the JSON-LD processor will try to convert datatyped literals to JSON native types instead of using the expanded object form when converting from RDF. `xsd:boolean` values will be converted to `true` or `false`. `xsd:integer` and `xsd:double` values will be converted to JSON numbers.
    # @option options [Boolean] :rename_bnodes (true)
    #   Rename bnodes as part of expansion, or keep them the same.
    # @yield [api]
    # @yieldparam [API]
    def initialize(input, context, options = {}, &block)
      @options = {:compactArrays => true}.merge(options)
      options = {:rename_bnodes => true}.merge(options)
      @namer = options[:rename_bnodes] ? BlankNodeNamer.new("b") : BlankNodeMapper.new
      @value = case input
      when Array, Hash then input.dup
      when IO, StringIO then JSON.parse(input.read)
      when String
        content = nil
        @options = {:base => input}.merge(@options)
        RDF::Util::File.open_file(input, OPEN_OPTS) {|f| content = JSON.parse(f.read)}
        content
      end
      @context = Context.new(@options)
      @context = @context.parse(context) if context
      
      if block_given?
        case block.arity
          when 0, -1 then instance_eval(&block)
          else block.call(self)
        end
      end
    end
    
    ##
    # Expands the given input according to the steps in the Expansion Algorithm. The input must be copied, expanded and returned
    # if there are no errors. If the expansion fails, an appropriate exception must be thrown.
    #
    # The resulting `Array` either returned or yielded
    #
    # @param [String, #read, Hash, Array] input
    #   The JSON-LD object to copy and perform the expansion upon.
    # @param [String, #read, Hash, Array, JSON::LD::Context] context
    #   An external context to use additionally to the context embedded in input when expanding the input.
    # @param  [Hash{Symbol => Object}] options
    #   See options in {JSON::LD::API#initialize}
    # @raise [InvalidContext]
    # @yield jsonld
    # @yieldparam [Array<Hash>] jsonld
    #   The expanded JSON-LD document
    # @return [Array<Hash>]
    #   The expanded JSON-LD document
    # @see http://json-ld.org/spec/latest/json-ld-api/#expansion-algorithm
    def self.expand(input, context = nil, options = {})
      result = nil
      API.new(input, context, options) do |api|
        result = api.expand(api.value, nil, api.context)
      end

      # If, after the algorithm outlined above is run, the resulting element is an
      # JSON object with just a @graph property, element is set to the value of @graph's value.
      result = result['@graph'] if result.is_a?(Hash) && result.keys == %w(@graph)

      # Finally, if element is a JSON object, it is wrapped into an array.
      result = [result].compact unless result.is_a?(Array)
      yield result if block_given?
      result
    end

    ##
    # Compacts the given input according to the steps in the Compaction Algorithm. The input must be copied, compacted and
    # returned if there are no errors. If the compaction fails, an appropirate exception must be thrown.
    #
    # If no context is provided, the input document is compacted using the top-level context of the document
    #
    # The resulting `Hash` is either returned or yielded, if a block is given.
    #
    # @param [String, #read, Hash, Array] input
    #   The JSON-LD object to copy and perform the compaction upon.
    # @param [String, #read, Hash, Array, JSON::LD::Context] context
    #   The base context to use when compacting the input.
    # @param  [Hash{Symbol => Object}] options
    #   See options in {JSON::LD::API#initialize}
    #   Other options passed to {JSON::LD::API.expand}
    # @yield jsonld
    # @yieldparam [Hash] jsonld
    #   The compacted JSON-LD document
    # @return [Hash]
    #   The compacted JSON-LD document
    # @raise [InvalidContext, ProcessingError]
    # @see http://json-ld.org/spec/latest/json-ld-api/#compaction-algorithm
    def self.compact(input, context, options = {})
      expanded = result = nil

      # 1) Perform the Expansion Algorithm on the JSON-LD input.
      #    This removes any existing context to allow the given context to be cleanly applied.
      expanded = API.expand(input, nil, options.merge(:debug => nil))

      API.new(expanded, context, options) do
        debug(".compact") {"expanded input: #{expanded.to_json(JSON_STATE)}"}
        result = compact(value, nil)

        # xxx) Add the given context to the output
        ctx = self.context.serialize
        if result.is_a?(Array)
          kwgraph = self.context.compact_iri('@graph', :vocab => true, :quiet => true)
          result = result.empty? ? {} : {kwgraph => result}
        end
        result = ctx.merge(result) unless ctx.empty?
      end
      yield result if block_given?
      result
    end

    ##
    # This algorithm flattens an expanded JSON-LD document by collecting all properties of a node in a single JSON object and labeling all blank nodes with blank node identifiers. This resulting uniform shape of the document, may drastically simplify the code required to process JSON-LD data in certain applications.
    #
    # The resulting `Array` is either returned, or yielded if a block is given.
    #
    # @param [String, #read, Hash, Array] input
    #   The JSON-LD object or array of JSON-LD objects to flatten or an IRI referencing the JSON-LD document to flatten.
    # @param [String, #read, Hash, Array, JSON::LD::EvaluationContext] context
    #   An optional external context to use additionally to the context embedded in input when expanding the input.
    # @param  [Hash{Symbol => Object}] options
    #   See options in {JSON::LD::API#initialize}
    #   Other options passed to {JSON::LD::API.expand}
    # @yield jsonld
    # @yieldparam [Hash] jsonld
    #   The framed JSON-LD document
    # @return [Array<Hash>]
    #   The framed JSON-LD document
    # @raise [InvalidFrame]
    # @see http://json-ld.org/spec/latest/json-ld-api/#framing-algorithm
    def self.flatten(input, context, options = {})
      flattened = []

      # Expand input to simplify processing
      expanded_input = API.expand(input, nil, options)

      # Initialize input using frame as context
      API.new(expanded_input, nil, options) do
        debug(".flatten") {"expanded input: #{value.to_json(JSON_STATE)}"}

        # Initialize node map to a JSON object consisting of a single member whose key is @default and whose value is an empty JSON object.
        node_map = Hash.ordered
        node_map['@default'] = Hash.ordered
        self.generate_node_map(value, node_map)

        default_graph = node_map['@default']
        node_map.keys.kw_sort.reject {|k| k == '@default'}.each do |graph_name|
          graph = node_map[graph_name]
          entry = default_graph[graph_name] ||= {'@id' => graph_name}
          nodes = entry['@graph'] ||= []
          graph.keys.kw_sort.each do |id|
            nodes << graph[id]
          end
        end
        default_graph.keys.kw_sort.each do |id|
          flattened << default_graph[id]
        end

        if context && !flattened.empty?
          # Otherwise, return the result of compacting flattened according the Compaction algorithm passing context ensuring that the compaction result uses the @graph keyword (or its alias) at the top-level, even if the context is empty or if there is only one element to put in the @graph array. This ensures that the returned document has a deterministic structure.
          compacted = compact(flattened, nil)
          compacted = [compacted] unless compacted.is_a?(Array)
          kwgraph = self.context.compact_iri('@graph', :quiet => true)
          flattened = self.context.serialize.merge(kwgraph => compacted)
        end
      end

      yield flattened if block_given?
      flattened
    end

    ##
    # Frames the given input using the frame according to the steps in the Framing Algorithm. The input is used to build the
    # framed output and is returned if there are no errors. If there are no matches for the frame, null must be returned.
    # Exceptions must be thrown if there are errors.
    #
    # The resulting `Array` is either returned, or yielded if a block is given.
    #
    # @param [String, #read, Hash, Array] input
    #   The JSON-LD object to copy and perform the framing on.
    # @param [String, #read, Hash, Array] frame
    #   The frame to use when re-arranging the data.
    # @param  [Hash{Symbol => Object}] options
    #   See options in {JSON::LD::API#initialize}
    #   Other options passed to {JSON::LD::API.expand}
    # @option options [Boolean] :embed (true)
    #   a flag specifying that objects should be directly embedded in the output,
    #   instead of being referred to by their IRI.
    # @option options [Boolean] :explicit (false)
    #   a flag specifying that for properties to be included in the output,
    #   they must be explicitly declared in the framing context.
    # @option options [Boolean] :omitDefault (false)
    #   a flag specifying that properties that are missing from the JSON-LD
    #   input should be omitted from the output.
    # @yield jsonld
    # @yieldparam [Hash] jsonld
    #   The framed JSON-LD document
    # @return [Array<Hash>]
    #   The framed JSON-LD document
    # @raise [InvalidFrame]
    # @see http://json-ld.org/spec/latest/json-ld-api/#framing-algorithm
    def self.frame(input, frame, options = {})
      result = nil
      match_limit = 0
      framing_state = {
        :embed       => true,
        :explicit    => false,
        :omitDefault => false,
        :embeds      => nil,
      }
      framing_state[:embed] = options[:embed] if options.has_key?(:embed)
      framing_state[:explicit] = options[:explicit] if options.has_key?(:explicit)
      framing_state[:omitDefault] = options[:omitDefault] if options.has_key?(:omitDefault)

      # de-reference frame to create the framing object
      frame = case frame
      when Hash then frame.dup
      when IO, StringIO then JSON.parse(frame.read)
      when String
        content = nil
        RDF::Util::File.open_file(frame, OPEN_OPTS) {|f| content = JSON.parse(f.read)}
        content
      end

      # Expand frame to simplify processing
      expanded_frame = API.expand(frame)
      
      # Expand input to simplify processing
      expanded_input = API.expand(input)

      # Initialize input using frame as context
      API.new(expanded_input, nil, options) do
        #debug(".frame") {"context from frame: #{context.inspect}"}
        debug(".frame") {"raw frame: #{frame.to_json(JSON_STATE)}"}
        debug(".frame") {"expanded frame: #{expanded_frame.to_json(JSON_STATE)}"}
        debug(".frame") {"expanded input: #{value.to_json(JSON_STATE)}"}

        # Get framing nodes from expanded input, replacing Blank Node identifiers as necessary
        all_nodes = Hash.ordered
        old_dbg, @options[:debug] = @options[:debug], nil
        depth do
          generate_node_map(value, all_nodes)
        end
        @options[:debug] = old_dbg
        @node_map = all_nodes['@default']
        debug(".frame") {"node_map: #{@node_map.to_json(JSON_STATE)}"}

        result = []
        frame(framing_state, @node_map, (expanded_frame.first || {}), result, nil)
        debug(".frame") {"after frame: #{result.to_json(JSON_STATE)}"}
        
        # Initalize context from frame
        @context = depth {@context.parse(frame['@context'])}
        # Compact result
        compacted = depth {compact(result, nil)}
        compacted = [compacted] unless compacted.is_a?(Array)

        # Add the given context to the output
        kwgraph = context.compact_iri('@graph', :quiet => true)
        result = context.serialize.merge({kwgraph => compacted})
        debug(".frame") {"after compact: #{result.to_json(JSON_STATE)}"}
        result = cleanup_preserve(result)
      end

      yield result if block_given?
      result
    end

    ##
    # Processes the input according to the RDF Conversion Algorithm, calling the provided callback for each triple generated.
    #
    # @param [String, #read, Hash, Array] input
    #   The JSON-LD object to process when outputting statements.
    # @param [String, #read, Hash, Array, JSON::LD::Context] context
    #   An external context to use additionally to the context embedded in input when expanding the input.
    # @param [{Symbol,String => Object}] options
    #   See options in {JSON::LD::API#initialize}
    #   Options passed to {JSON::LD::API.expand}
    # @raise [InvalidContext]
    # @return [Array<RDF::Statement>] if no block given
    # @yield statement
    # @yieldparam [RDF::Statement] statement
    def self.toRDF(input, context = nil, options = {}, &block)
      results = []
      results.extend(RDF::Enumerable)

      # Expand input to simplify processing
      expanded_input = API.expand(input, context, options)

      API.new(expanded_input, context, options) do
        # 1) Perform the Expansion Algorithm on the JSON-LD input.
        #    This removes any existing context to allow the given context to be cleanly applied.
        debug(".toRDF") {"expanded input: #{expanded_input.to_json(JSON_STATE)}"}

        # Generate _nodeMap_
        node_map = Hash.ordered
        node_map['@default'] = Hash.ordered
        generate_node_map(expanded_input, node_map)
        debug(".toRDF") {"node map: #{node_map.to_json(JSON_STATE)}"}

        # Start generating statements
        node_map.each do |graph_name, graph|
          context = as_resource(graph_name) unless graph_name == '@default'
          debug(".toRDF") {"context: #{context ? context.to_ntriples : 'null'}"}
          graph_to_rdf(graph).each do |statement|
            statement.context = context if context
            if block_given?
              yield statement
            else
              results << statement
            end
          end
        end
      end
      results
    end
    
    ##
    # Take an ordered list of RDF::Statements and turn them into a JSON-LD document.
    #
    # The resulting `Array` is either returned or yielded, if a block is given.
    #
    # @param [Array<RDF::Statement>] input
    # @param  [Hash{Symbol => Object}] options
    #   See options in {JSON::LD::API#initialize}
    # @yield jsonld
    # @yieldparam [Hash] jsonld
    #   The JSON-LD document in expanded form
    # @return [Array<Hash>]
    #   The JSON-LD document in expanded form
    def self.fromRDF(input, options = {}, &block)
      options = {:useNativeTypes => true}.merge(options)
      result = nil

      API.new(nil, nil, options) do |api|
        result = api.from_statements(input)
      end

      yield result if block_given?
      result
    end
  end
end

