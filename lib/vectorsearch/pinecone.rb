# frozen_string_literal: true

module Vectorsearch
  class Pinecone < Base
    # Initialize the Pinecone client
    # @param environment [String] The environment to use
    # @param api_key [String] The API key to use
    # @param index_name [String] The name of the index to use
    # @param llm [Symbol] The LLM to use
    # @param llm_api_key [String] The API key for the LLM
    def initialize(environment:, api_key:, index_name:, llm:, llm_api_key:)
      depends_on "pinecone"
      require "pinecone"

      ::Pinecone.configure do |config|
        config.api_key = api_key
        config.environment = environment
      end

      @client = ::Pinecone::Client.new
      @index_name = index_name

      super(llm: llm, llm_api_key: llm_api_key)
    end

    # Add a list of texts to the index
    # @param texts [Array] The list of texts to add
    # @param namespace [String] The namespace to add the texts to
    # @return [Hash] The response from the server
    def add_texts(texts:, namespace: '')
      vectors = texts.map do |text|
        {
          # TODO: Allows passing in your own IDs
          id: SecureRandom.uuid,
          namespace: namespace,
          metadata: { content: text },
          values: llm_client.embed(text: text)
        }
      end

      index = client.index(index_name)

      index.upsert(vectors: vectors)
    end

    # Create the index with the default schema
    # @return [Hash] The response from the server
    def create_default_schema
      client.create_index(
        metric: DEFAULT_METRIC,
        name: index_name,
        dimension: default_dimension
      )
    end

    # Search for similar texts
    # @param query [String] The text to search for
    # @param k [Integer] The number of results to return
    # @param namespace [String] The namespace to search in
    # @return [Array] The list of results
    def similarity_search(
      query:,
      k: 4,
      namespace: ''
    )
      embedding = llm_client.embed(text: query)

      similarity_search_by_vector(
        embedding: embedding,
        k: k,
        namespace: namespace
      )
    end

    # Search for similar texts by embedding
    # @param embedding [Array] The embedding to search for
    # @param k [Integer] The number of results to return
    # @param namespace [String] The namespace to search in
    # @return [Array] The list of results
    def similarity_search_by_vector(embedding:, k: 4, namespace: '')
      index = client.index(index_name)

      response = index.query(
        vector: embedding,
        namespace: namespace,
        top_k: k,
        include_values: true,
        include_metadata: true
      )
      response.dig("matches")
    end

    # Ask a question and return the answer
    # @param question [String] The question to ask
    # @param namespace [String] The namespace to search in
    # @return [String] The answer to the question
    def ask(question:, namespace: '')
      search_results = similarity_search(query: question, namespace: namespace)

      context = search_results.map do |result|
        result.dig("metadata").to_s
      end
      context = context.join("\n---\n")

      prompt = generate_prompt(question: question, context: context)

      llm_client.chat(prompt: prompt)
    end
  end
end
