class Captain::Knowledge::GapClusterer
  MIN_CLUSTER_SIZE = 3
  MAX_DISTANCE = 0.25
  EMBEDDING_DIMENSIONS = 1536
  MESSAGE_LIMIT = 12
  MESSAGE_CHARACTER_LIMIT = 800

  def initialize(account)
    @embedding_service = Captain::Llm::EmbeddingService.new(account_id: account.id)
  end

  def clusters(conversations)
    groups = conversations.filter_map { |conversation| sample(conversation) }.each_with_object([]) do |entry, clusters|
      closest = clusters.min_by { |cluster| distance(cluster.fetch(:centroid), entry.fetch(:embedding)) }
      if closest && distance(closest.fetch(:centroid), entry.fetch(:embedding)) < MAX_DISTANCE
        closest.fetch(:samples) << entry
        closest[:centroid] = centroid(closest.fetch(:samples))
      else
        clusters << { centroid: entry.fetch(:embedding), samples: [entry] }
      end
    end
    groups.select { |group| group.fetch(:samples).length >= MIN_CLUSTER_SIZE }
  end

  private

  def sample(conversation)
    inquiry = message_text(conversation.messages.incoming)
    answer = message_text(conversation.messages.outgoing.where(sender_type: 'User'))
    return if inquiry.blank? || answer.blank?

    transcript = { question: inquiry, resolution: answer }.to_json
    vector = @embedding_service.get_embedding(transcript)
    raise ArgumentError, 'Knowledge gap embeddings must be 1536-dimensional' unless vector.length == EMBEDDING_DIMENSIONS

    { conversation_id: conversation.id, transcript: transcript, embedding: normalize(vector) }
  end

  def message_text(scope)
    scope.where(private: false).where.not(content: [nil, '']).reorder(created_at: :desc, id: :desc)
         .limit(MESSAGE_LIMIT).pluck(:content).reverse.map { |content| content.truncate(MESSAGE_CHARACTER_LIMIT) }.join("\n")
  end

  def centroid(samples)
    vectors = samples.pluck(:embedding)
    normalize(vectors.transpose.map(&:sum))
  end

  def normalize(vector)
    magnitude = Math.sqrt(vector.sum { |component| component**2 })
    raise ArgumentError, 'Invalid knowledge gap embedding' unless magnitude.finite? && magnitude.positive?

    vector.map { |component| component / magnitude }
  end

  def distance(left, right)
    1.0 - left.each_index.sum { |index| left[index] * right[index] }
  end
end
