require "spec_helper"
require "timeout"

describe "Tokenizer" do
  let(:parser) { @context["handlebars"] }
  let(:lexer) { @context["handlebars"]["lexer"] }

  before(:all) do
    @compiles = true
  end
  Token = Struct.new(:name, :text)

  def tokenize(string)
    lexer.setInput(string)
    out = []

    while token = lexer.lex
      # p token
      result = parser.terminals_[token] || token
      # p result
      break if !result || result == "EOF" || result == "INVALID"
      out << Token.new(result, lexer.yytext)
    end

    out
  end

  RSpec::Matchers.define :match_tokens do |tokens|
    match do |result|
      result.map(&:name).should == tokens
    end
  end

  RSpec::Matchers.define :be_token do |name, string|
    match do |token|
      token.name.should == name
      token.text.should == string
    end
  end

  it "tokenizes a simple mustache as 'OPEN ID CLOSE'" do
    result = tokenize("{{foo}}")
    result.should match_tokens(%w(OPEN ID CLOSE))
    result[1].should be_token("ID", "foo")
  end

  it "supports escaping delimiters" do
    result = tokenize("{{foo}} \\{{bar}} {{baz}}")
    result.should match_tokens(%w(OPEN ID CLOSE CONTENT CONTENT OPEN ID CLOSE))

    result[4].should be_token("CONTENT", "{{bar}} ")
  end

  it "supports escaping multiple delimiters" do
    result = tokenize("{{foo}} \\{{bar}} \\{{baz}}")
    result.should match_tokens(%w(OPEN ID CLOSE CONTENT CONTENT CONTENT))

    result[3].should be_token("CONTENT", " ")
    result[4].should be_token("CONTENT", "{{bar}} ")
    result[5].should be_token("CONTENT", "{{baz}}")
  end

  it "supports escaping a triple stash" do
    result = tokenize("{{foo}} \\{{{bar}}} {{baz}}")
    result.should match_tokens(%w(OPEN ID CLOSE CONTENT CONTENT OPEN ID CLOSE))

    result[4].should be_token("CONTENT", "{{{bar}}} ")
  end

  it "tokenizes a simple path" do
    result = tokenize("{{foo/bar}}")
    result.should match_tokens(%w(OPEN ID SEP ID CLOSE))
  end

  it "allows dot notation" do
    result = tokenize("{{foo.bar}}")
    result.should match_tokens(%w(OPEN ID SEP ID CLOSE))

    tokenize("{{foo.bar.baz}}").should match_tokens(%w(OPEN ID SEP ID SEP ID CLOSE))
  end

  it "allows path literals with []" do
    result = tokenize("{{foo.[bar]}}")
    result.should match_tokens(%w(OPEN ID SEP ID CLOSE))
  end

  it "allows multiple path literals on a line with []" do
    result = tokenize("{{foo.[bar]}}{{foo.[baz]}}")
    result.should match_tokens(%w(OPEN ID SEP ID CLOSE OPEN ID SEP ID CLOSE))
  end

  it "tokenizes {{.}} as OPEN ID CLOSE" do
    result = tokenize("{{.}}")
    result.should match_tokens(%w(OPEN ID CLOSE))
  end

  it "tokenizes a path as 'OPEN (ID SEP)* ID CLOSE'" do
    result = tokenize("{{../foo/bar}}")
    result.should match_tokens(%w(OPEN ID SEP ID SEP ID CLOSE))
    result[1].should be_token("ID", "..")
  end

  it "tokenizes a path with .. as a parent path" do
    result = tokenize("{{../foo.bar}}")
    result.should match_tokens(%w(OPEN ID SEP ID SEP ID CLOSE))
    result[1].should be_token("ID", "..")
  end

  it "tokenizes a path with this/foo as OPEN ID SEP ID CLOSE" do
    result = tokenize("{{this/foo}}")
    result.should match_tokens(%w(OPEN ID SEP ID CLOSE))
    result[1].should be_token("ID", "this")
    result[3].should be_token("ID", "foo")
  end

  it "tokenizes a simple mustache with spaces as 'OPEN ID CLOSE'" do
    result = tokenize("{{  foo  }}")
    result.should match_tokens(%w(OPEN ID CLOSE))
    result[1].should be_token("ID", "foo")
  end

  it "tokenizes a simple mustache with line breaks as 'OPEN ID ID CLOSE'" do
    result = tokenize("{{  foo  \n   bar }}")
    result.should match_tokens(%w(OPEN ID ID CLOSE))
    result[1].should be_token("ID", "foo")
  end

  it "tokenizes raw content as 'CONTENT'" do
    result = tokenize("foo {{ bar }} baz")
    result.should match_tokens(%w(CONTENT OPEN ID CLOSE CONTENT))
    result[0].should be_token("CONTENT", "foo ")
    result[4].should be_token("CONTENT", " baz")
  end

  it "tokenizes a partial as 'OPEN_PARTIAL ID CLOSE'" do
    result = tokenize("{{> foo}}")
    result.should match_tokens(%w(OPEN_PARTIAL ID CLOSE))
  end

  it "tokenizes a partial with context as 'OPEN_PARTIAL ID ID CLOSE'" do
    result = tokenize("{{> foo bar }}")
    result.should match_tokens(%w(OPEN_PARTIAL ID ID CLOSE))
  end

  it "tokenizes a partial without spaces as 'OPEN_PARTIAL ID CLOSE'" do
    result = tokenize("{{>foo}}")
    result.should match_tokens(%w(OPEN_PARTIAL ID CLOSE))
  end

  it "tokenizes a partial space at the end as 'OPEN_PARTIAL ID CLOSE'" do
    result = tokenize("{{>foo  }}")
    result.should match_tokens(%w(OPEN_PARTIAL ID CLOSE))
  end

  it "tokenizes a comment as 'COMMENT'" do
    result = tokenize("foo {{! this is a comment }} bar {{ baz }}")
    result.should match_tokens(%w(CONTENT COMMENT CONTENT OPEN ID CLOSE))
    result[1].should be_token("COMMENT", " this is a comment ")
  end

  it "tokenizes a block comment as 'COMMENT'" do
    result = tokenize("foo {{!-- this is a {{comment}} --}} bar {{ baz }}")
    result.should match_tokens(%w(CONTENT COMMENT CONTENT OPEN ID CLOSE))
    result[1].should be_token("COMMENT", " this is a {{comment}} ")
  end

  it "tokenizes a block comment with whitespace as 'COMMENT'" do
    result = tokenize("foo {{!-- this is a\n{{comment}}\n--}} bar {{ baz }}")
    result.should match_tokens(%w(CONTENT COMMENT CONTENT OPEN ID CLOSE))
    result[1].should be_token("COMMENT", " this is a\n{{comment}}\n")
  end

  it "tokenizes open and closing blocks as 'OPEN_BLOCK ID CLOSE ... OPEN_ENDBLOCK ID CLOSE'" do
    result = tokenize("{{#foo}}content{{/foo}}")
    result.should match_tokens(%w(OPEN_BLOCK ID CLOSE CONTENT OPEN_ENDBLOCK ID CLOSE))
  end

  it "tokenizes inverse sections as 'OPEN_INVERSE CLOSE'" do
    tokenize("{{^}}").should match_tokens(%w(OPEN_INVERSE CLOSE))
    tokenize("{{else}}").should match_tokens(%w(OPEN_INVERSE CLOSE))
    tokenize("{{ else }}").should match_tokens(%w(OPEN_INVERSE CLOSE))
  end

  it "tokenizes inverse sections with ID as 'OPEN_INVERSE ID CLOSE'" do
    result = tokenize("{{^foo}}")
    result.should match_tokens(%w(OPEN_INVERSE ID CLOSE))
    result[1].should be_token("ID", "foo")
  end

  it "tokenizes inverse sections with ID and spaces as 'OPEN_INVERSE ID CLOSE'" do
    result = tokenize("{{^ foo  }}")
    result.should match_tokens(%w(OPEN_INVERSE ID CLOSE))
    result[1].should be_token("ID", "foo")
  end

  it "tokenizes mustaches with params as 'OPEN ID ID ID CLOSE'" do
    result = tokenize("{{ foo bar baz }}")
    result.should match_tokens(%w(OPEN ID ID ID CLOSE))
    result[1].should be_token("ID", "foo")
    result[2].should be_token("ID", "bar")
    result[3].should be_token("ID", "baz")
  end

  it "tokenizes mustaches with String params as 'OPEN ID ID STRING CLOSE'" do
    result = tokenize("{{ foo bar \"baz\" }}")
    result.should match_tokens(%w(OPEN ID ID STRING CLOSE))
    result[3].should be_token("STRING", "baz")
  end

  it "tokenizes mustaches with String params using single quotes as 'OPEN ID ID STRING CLOSE'" do
    result = tokenize("{{ foo bar \'baz\' }}")
    result.should match_tokens(%w(OPEN ID ID STRING CLOSE))
    result[3].should be_token("STRING", "baz")
  end

  it "tokenizes String params with spaces inside as 'STRING'" do
    result = tokenize("{{ foo bar \"baz bat\" }}")
    result.should match_tokens(%w(OPEN ID ID STRING CLOSE))
    result[3].should be_token("STRING", "baz bat")
  end

  it "tokenizes String params with escapes quotes as 'STRING'" do
    result = tokenize(%|{{ foo "bar\\"baz" }}|)
    result.should match_tokens(%w(OPEN ID STRING CLOSE))
    result[2].should be_token("STRING", %{bar"baz})
  end

  it "tokenizes String params using single quotes with escapes quotes as 'STRING'" do
    result = tokenize(%|{{ foo 'bar\\'baz' }}|)
    result.should match_tokens(%w(OPEN ID STRING CLOSE))
    result[2].should be_token("STRING", %{bar'baz})
  end

  it "tokenizes numbers" do
    result = tokenize(%|{{ foo 1 }}|)
    result.should match_tokens(%w(OPEN ID INTEGER CLOSE))
    result[2].should be_token("INTEGER", "1")
  end

  it "tokenizes booleans" do
    result = tokenize(%|{{ foo true }}|)
    result.should match_tokens(%w(OPEN ID BOOLEAN CLOSE))
    result[2].should be_token("BOOLEAN", "true")

    result = tokenize(%|{{ foo false }}|)
    result.should match_tokens(%w(OPEN ID BOOLEAN CLOSE))
    result[2].should be_token("BOOLEAN", "false")
  end

  it "tokenizes hash arguments" do
    result = tokenize("{{ foo bar=baz }}")
    result.should match_tokens %w(OPEN ID ID EQUALS ID CLOSE)

    result = tokenize("{{ foo bar baz=bat }}")
    result.should match_tokens %w(OPEN ID ID ID EQUALS ID CLOSE)

    result = tokenize("{{ foo bar baz=1 }}")
    result.should match_tokens %w(OPEN ID ID ID EQUALS INTEGER CLOSE)

    result = tokenize("{{ foo bar baz=true }}")
    result.should match_tokens %w(OPEN ID ID ID EQUALS BOOLEAN CLOSE)

    result = tokenize("{{ foo bar baz=false }}")
    result.should match_tokens %w(OPEN ID ID ID EQUALS BOOLEAN CLOSE)

    result = tokenize("{{ foo bar\n  baz=bat }}")
    result.should match_tokens %w(OPEN ID ID ID EQUALS ID CLOSE)

    result = tokenize("{{ foo bar baz=\"bat\" }}")
    result.should match_tokens %w(OPEN ID ID ID EQUALS STRING CLOSE)

    result = tokenize("{{ foo bar baz=\"bat\" bam=wot }}")
    result.should match_tokens %w(OPEN ID ID ID EQUALS STRING ID EQUALS ID CLOSE)

    result = tokenize("{{foo omg bar=baz bat=\"bam\"}}")
    result.should match_tokens %w(OPEN ID ID ID EQUALS ID ID EQUALS STRING CLOSE)
    result[2].should be_token("ID", "omg")
  end

  it "tokenizes special @ identifiers" do
    result = tokenize("{{ @foo }}")
    result.should match_tokens %w( OPEN DATA CLOSE )
    result[1].should be_token("DATA", "foo")

    result = tokenize("{{ foo @bar }}")
    result.should match_tokens %w( OPEN ID DATA CLOSE )
    result[2].should be_token("DATA", "bar")

    result = tokenize("{{ foo bar=@baz }}")
    result.should match_tokens %w( OPEN ID ID EQUALS DATA CLOSE )
    result[4].should be_token("DATA", "baz")
  end

  it "does not time out in a mustache with a single } followed by EOF" do
    Timeout.timeout(1) { tokenize("{{foo}").should match_tokens(%w(OPEN ID)) }
  end

  it "does not time out in a mustache when invalid ID characters are used" do
    Timeout.timeout(1) { tokenize("{{foo & }}").should match_tokens(%w(OPEN ID)) }
  end

  describe "Redpie Tests" do
    it "should parse indirect ID lookups which use {} as identifiers - {{ {bar} }}" do
      result = tokenize("{{ {bar} }}")
      result.should match_tokens(%w(OPEN ID CLOSE))
      result[1].should be_token("ID", "{bar}")
      result[2].should be_token("CLOSE", "}}")
    end

    it "should parse indirect ID lookups which use {} as identifiers - {{ ~{bar} }}" do
      result = tokenize("{{ ~{bar} }}")
      result.should match_tokens(%w(OPEN ID CLOSE))
      result[1].should be_token("ID", "~{bar}")
      result[2].should be_token("CLOSE", "}}")
    end

    it "should parse indirect ID lookups which use {} as identifiers - {{ foo.{bar} }}" do
      result = tokenize("{{ foo.{bar} }}")
      result.should match_tokens(%w(OPEN ID SEP ID CLOSE))
      result[1].should be_token("ID", "foo")
      result[3].should be_token("ID", "{bar}")
      result[4].should be_token("CLOSE", "}}")
    end

    it "should parse indirect ID lookups which use {} as identifiers - {{ ~foo.{bar} }}" do
      result = tokenize("{{ ~foo.{bar} }}")
      result.should match_tokens(%w(OPEN ID SEP ID CLOSE))
      result[1].should be_token("ID", "~foo")
      result[3].should be_token("ID", "{bar}")
      result[4].should be_token("CLOSE", "}}")
    end

    it "should parse indirect ID lookups which use {} as identifiers - {{ foo.{~bar} }}" do
      result = tokenize("{{ foo.{~bar} }}")
      result.should match_tokens(%w(OPEN ID SEP ID CLOSE))
      result[1].should be_token("ID", "foo")
      result[3].should be_token("ID", "{~bar}")
      result[4].should be_token("CLOSE", "}}")
    end

    it "should parse indirect ID lookups which use {} as identifiers - {{ {foo.bar} }}" do
      result = tokenize("{{ {foo.bar} }}")
      result.should match_tokens(%w(OPEN ID SEP ID CLOSE))
      result[1].should be_token("ID", "{foo")
      result[3].should be_token("ID", "bar}")
      result[4].should be_token("CLOSE", "}}")
    end

    it "should parse indirect ID lookups which use {} as identifiers - {{ ~{foo.bar} }}" do
      result = tokenize("{{ ~{foo.bar} }}")
      result.should match_tokens(%w(OPEN ID SEP ID CLOSE))
      result[1].should be_token("ID", "~{foo")
      result[3].should be_token("ID", "bar}")
      result[4].should be_token("CLOSE", "}}")
    end

    it "should parse indirect ID lookups which use {} as identifiers - {{ ~{~foo.bar} }}" do
      result = tokenize("{{ ~{~foo.bar} }}")
      result.should match_tokens(%w(OPEN ID SEP ID CLOSE))
      result[1].should be_token("ID", "~{~foo")
      result[3].should be_token("ID", "bar}")
      result[4].should be_token("CLOSE", "}}")
    end

    it "should parse indirect ID lookups which use {} as identifiers - {{ foo.{~bar}.baz }}" do
      result = tokenize("{{ foo.{~bar}.baz }}")
      result.should match_tokens(%w(OPEN ID SEP ID SEP ID CLOSE))
      result[1].should be_token("ID", "foo")
      result[3].should be_token("ID", "{~bar}")
      result[5].should be_token("ID", "baz")
      result[6].should be_token("CLOSE", "}}")
    end

    it "should parse indirect ID lookups which use {} as identifiers - {{ {~bar}.baz }}" do
      result = tokenize("{{ {~bar}.baz }}")
      result.should match_tokens(%w(OPEN ID SEP ID CLOSE))
      result[1].should be_token("ID", "{~bar}")
      result[3].should be_token("ID", "baz")
      result[4].should be_token("CLOSE", "}}")
    end

    it "should parse indirect ID lookups which use {} as identifiers - {{ {foo}.{bar} }}" do
      result = tokenize("{{ {foo}.{bar} }}")
      result.should match_tokens(%w(OPEN ID SEP ID CLOSE))
      result[1].should be_token("ID", "{foo}")
      result[3].should be_token("ID", "{bar}")
      result[4].should be_token("CLOSE", "}}")
    end

    it "should parse indirect ID lookups which use {} as identifiers - {{ ../{bar} }}" do
      result = tokenize("{{ ../{bar} }}")
      result.should match_tokens(%w(OPEN ID SEP ID CLOSE))
      result[1].should be_token("ID", "..")
      result[3].should be_token("ID", "{bar}")
      result[4].should be_token("CLOSE", "}}")
    end

    it "should parse indirect ID lookups which use {} as identifiers - {{ ...{bar} }}" do
      result = tokenize("{{ ...{bar} }}")
      result.should match_tokens(%w(OPEN ID SEP ID CLOSE))
      result[1].should be_token("ID", "..")
      result[3].should be_token("ID", "{bar}")
      result[4].should be_token("CLOSE", "}}")
    end

    it "should parse indirect ID lookups which use {} as identifiers - {{ {schema.name} test}}" do
      result = tokenize("{{ {schema.name} test}}")
      result.should match_tokens(%w(OPEN ID SEP ID ID CLOSE))
      
      result[1].should be_token("ID", "{schema")
      result[3].should be_token("ID", "name}")
      result[4].should be_token("ID", "test")
      result[5].should be_token("CLOSE", "}}")
    end

    it "should parse indirect ID lookups which use {} as identifiers - {{ {schema} test}}" do
      result = tokenize("{{ {schema} test}}")
      result.should match_tokens(%w(OPEN ID ID CLOSE))

      result[1].should be_token("ID", "{schema}")
      result[2].should be_token("ID", "test")
      result[3].should be_token("CLOSE", "}}")
    end

    it "should parse indirect ID lookups which use {} as identifiers - {{ {schema} ~test}}" do
      result = tokenize("{{ {schema} ~test}}")
      result.should match_tokens(%w(OPEN ID ID CLOSE))

      result[1].should be_token("ID", "{schema}")
      result[2].should be_token("ID", "~test")
      result[3].should be_token("CLOSE", "}}")
    end

    it "should parse indirect ID lookups which use {} as identifiers - {{test ~{~a.b} }}" do
      result = tokenize("{{test ~{~a.b} }}")
      result.should match_tokens(%w(OPEN ID ID SEP ID CLOSE))

      result[1].should be_token("ID", "test")
      result[2].should be_token("ID", "~{~a")
      result[4].should be_token("ID", "b}")
      result[5].should be_token("CLOSE", "}}")
    end
  end
end
