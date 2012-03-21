# coding: utf-8
$:.unshift "."
require 'spec_helper'

describe JSON::LD::API do
  before(:each) { @debug = []}

  describe ".expand" do
    {
      "empty doc" => {
        :input => {},
        :output => {}
      },
      "coerced IRI" => {
        :input => {
          "@context" => {
            "a" => {"@id" => "http://example.com/a"},
            "b" => {"@id" => "http://example.com/b", "@type" => "@id"},
            "c" => {"@id" => "http://example.com/c"},
          },
          "@id" => "a",
          "b"   => "c"
        },
        :output => {
          "@id" => "http://example.com/a",
          "http://example.com/b" => {"@id" =>"http://example.com/c"}
        }
      },
      "coerced IRI in array" => {
        :input => {
          "@context" => {
            "a" => {"@id" => "http://example.com/a"},
            "b" => {"@id" => "http://example.com/b", "@type" => "@id"},
            "c" => {"@id" => "http://example.com/c"},
          },
          "@id" => "a",
          "b"   => ["c"]
        },
        :output => {
          "@id" => "http://example.com/a",
          "http://example.com/b" => [{"@id" => "http://example.com/c"}]
        }
      },
      "empty term" => {
        :input => {
          "@context" => {"" => "http://example.com/"},
          "@id" => "",
          "@type" => "#{RDF::RDFS.Resource}"
        },
        :output => {
          "@id" => "http://example.com/",
          "@type" => "#{RDF::RDFS.Resource}"
        }
      },
      "@list coercion" => {
        :input => {
          "@context" => {
            "foo" => {"@id" => "http://example.com/foo", "@container" => "@list"}
          },
          "foo" => ["bar"]
        },
        :output => {
          "http://example.com/foo" => {"@list" => ["bar"]}
        }
      }
    }.each_pair do |title, params|
      it title do
        jld = JSON::LD::API.expand(params[:input], nil, :debug => @debug)
        jld.should produce(params[:output], @debug)
      end
    end

    context "with relative IRIs" do
      {
        "base" => {
          :input => {
            "@id" => "",
            "@type" => "#{RDF::RDFS.Resource}"
          },
          :output => {
            "@id" => "http://example.org/",
            "@type" => "#{RDF::RDFS.Resource}"
          }
        },
        "relative" => {
          :input => {
            "@id" => "a/b",
            "@type" => "#{RDF::RDFS.Resource}"
          },
          :output => {
            "@id" => "http://example.org/a/b",
            "@type" => "#{RDF::RDFS.Resource}"
          }
        },
        "hash" => {
          :input => {
            "@id" => "#a",
            "@type" => "#{RDF::RDFS.Resource}"
          },
          :output => {
            "@id" => "http://example.org/#a",
            "@type" => "#{RDF::RDFS.Resource}"
          }
        },
      }.each do |title, params|
        it title do
          jld = JSON::LD::API.expand(params[:input], nil, :base_uri => "http://example.org/", :debug => @debug)
          jld.should produce(params[:output], @debug)
        end
      end
    end

    context "keyword aliasing" do
      {
        "@id" => {
          :input => {
            "@context" => {"id" => "@id"},
            "id" => "",
            "@type" => "#{RDF::RDFS.Resource}"
          },
          :output => {
            "@id" => "",
            "@type" => "#{RDF::RDFS.Resource}"
          }
        },
        "@type" => {
          :input => {
            "@context" => {"type" => "@type"},
            "type" => RDF::RDFS.Resource.to_s,
            "foo" => {"@value" => "bar", "type" => "baz"}
          },
          :output => {
            "@type" => RDF::RDFS.Resource.to_s,
            "foo" => {"@value" => "bar", "@type" => "baz"}
          }
        },
        "@language" => {
          :input => {
            "@context" => {"language" => "@language"},
            "foo" => {"@value" => "bar", "language" => "baz"}
          },
          :output => {
            "foo" => {"@value" => "bar", "@language" => "baz"}
          }
        },
        "@value" => {
          :input => {
            "@context" => {"literal" => "@value"},
            "foo" => {"literal" => "bar"}
          },
          :output => {
            "foo" => {"@value" => "bar"}
          }
        },
        "@list" => {
          :input => {
            "@context" => {"list" => "@list"},
            "foo" => {"list" => ["bar"]}
          },
          :output => {
            "foo" => {"@list" => ["bar"]}
          }
        },
      }.each do |title, params|
        it title do
          jld = JSON::LD::API.expand(params[:input], nil, :debug => @debug)
          jld.should produce(params[:output], @debug)
        end
      end
    end

    context "native types" do
      {
        "true" => {
          :input => {
            "@context" => {"e" => "http://example.org/vocab#"},
            "e:bool" => true
          },
          :output => {
            "http://example.org/vocab#bool" => {"@value" => "true", "@type" => RDF::XSD.boolean.to_s}
          }
        },
        "false" => {
          :input => {
            "@context" => {"e" => "http://example.org/vocab#"},
            "e:bool" => false
          },
          :output => {
            "http://example.org/vocab#bool" => {"@value" => "false", "@type" => RDF::XSD.boolean.to_s}
          }
        },
        "double" => {
          :input => {
            "@context" => {"e" => "http://example.org/vocab#"},
            "e:double" => 1.23
          },
          :output => {
            "http://example.org/vocab#double" => {"@value" => "1.23E0", "@type" => RDF::XSD.double.to_s}
          }
        },
        "double-zero" => {
          :input => {
            "@context" => {"e" => "http://example.org/vocab#"},
            "e:double-zero" => 0.0e0
          },
          :output => {
            "http://example.org/vocab#double-zero" => {"@value" => "0.0E0", "@type" => RDF::XSD.double.to_s}
          }
        },
        "integer" => {
          :input => {
            "@context" => {"e" => "http://example.org/vocab#"},
            "e:integer" => 123
          },
          :output => {
            "http://example.org/vocab#integer" => {"@value" => "123", "@type" => RDF::XSD.integer.to_s}
          }
        },
      }.each do |title, params|
        it title do
          jld = JSON::LD::API.expand(params[:input], nil, :debug => @debug)
          jld.should produce(params[:output], @debug)
        end
      end
    end

    context "exceptions" do
      {
        "@list containing @list" => {
          :input => {
            "foo" => {"@list" => [{"@list" => ["baz"]}]}
          },
          :exception => JSON::LD::ProcessingError::ListOfLists
        },
        "@list containing @list (with coercion)" => {
          :input => {
            "@context" => {"foo" => {"@container" => "@list"}},
            "foo" => [{"@list" => ["baz"]}]
          },
          :exception => JSON::LD::ProcessingError::ListOfLists
        },
        "@list containing array" => {
          :input => {
            "foo" => {"@list" => [["baz"]]}
          },
          :exception => JSON::LD::ProcessingError::ListOfLists
        },
      }.each do |title, params|
        it title do
          lambda {JSON::LD::API.expand(params[:input], nil)}.should raise_error(params[:exception])
        end
      end
    end
  end
end
