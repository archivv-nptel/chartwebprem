class Captain::Mcp::ConversationTools
  class InvalidArguments < StandardError; end

  MAX_RESULTS = 25
  DEFAULT_RESULTS = 10
  CONVERSATION_URI = %r{\Achatwoot://conversations/([1-9]\d{0,9})\z}

  DESCRIPTION = 'Read the status and last activity of a conversation you can access.'.freeze
  RESOURCE_TEMPLATE = {
    uriTemplate: 'chatwoot://conversations/{display_id}',
    name: 'conversation',
    description: DESCRIPTION,
    mimeType: 'application/json'
  }.freeze

  TOOLS = [
    {
      name: 'chatwoot_search_conversations',
      description: 'Search conversations you can access by contact name or email.',
      annotations: { readOnlyHint: true },
      inputSchema: {
        type: 'object', additionalProperties: false,
        properties: {
          status: { type: 'string', enum: Conversation.statuses.keys },
          query: { type: 'string', minLength: 1, maxLength: 200 },
          limit: { type: 'integer', minimum: 1, maximum: MAX_RESULTS, default: DEFAULT_RESULTS }
        }
      }
    },
    {
      name: 'chatwoot_add_private_note',
      description: 'Add an internal note to a conversation you can access.',
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false },
      inputSchema: {
        type: 'object', additionalProperties: false, required: %w[conversation_display_id content],
        properties: {
          conversation_display_id: { type: 'integer', minimum: 1, maximum: 2_147_483_647 },
          content: { type: 'string', minLength: 1, maxLength: 10_000 }
        }
      }
    },
    {
      name: 'chatwoot_get_contact_profile',
      description: 'Find a contact by email and list their recent conversations you can access.',
      annotations: { readOnlyHint: true },
      inputSchema: {
        type: 'object', additionalProperties: false, required: %w[email],
        properties: { email: { type: 'string', minLength: 1, maxLength: 254 } }
      }
    }
  ].freeze

  SCHEMAS = TOOLS.to_h { |tool| [tool.fetch(:name), JSONSchemer.schema(tool.fetch(:inputSchema).deep_stringify_keys)] }.freeze

  def initialize(account:, user:, account_user:)
    @account = account
    @user = user
    @account_user = account_user
  end

  def call(name, arguments)
    raise InvalidArguments unless SCHEMAS[name]&.valid?(arguments)

    case name
    when 'chatwoot_search_conversations' then search(arguments)
    when 'chatwoot_add_private_note' then add_note(arguments)
    when 'chatwoot_get_contact_profile' then contact_profile(arguments.fetch('email'))
    end
  end

  def read(uri)
    display_id = CONVERSATION_URI.match(uri.to_s)&.[](1)&.to_i
    raise InvalidArguments unless display_id && display_id <= 2_147_483_647

    summary(find_conversation(display_id))
  end

  private

  def conversations
    @conversations ||= Conversations::PermissionFilterService.new(@account.conversations, @user, @account).perform
  end

  def search(arguments)
    scope = conversations
    scope = scope.where(status: arguments['status']) if arguments.key?('status')
    scope = filter_contacts(scope, arguments['query']) if arguments.key?('query')
    scope.order(last_activity_at: :desc, id: :desc).limit(arguments.fetch('limit', DEFAULT_RESULTS)).map { |record| summary(record) }
  end

  def filter_contacts(scope, query)
    term = query.strip
    raise InvalidArguments if term.blank?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
    contacts = Contact.arel_table
    scope.joins(:contact).where(contacts[:name].matches(pattern).or(contacts[:email].matches(pattern)))
  end

  def add_note(arguments)
    content = arguments.fetch('content')
    raise InvalidArguments if content.blank?

    conversation = find_conversation(arguments.fetch('conversation_display_id'))
    message = Messages::MessageBuilder.new(@user, conversation, { content: content, private: true }).perform
    { message_id: message.id, conversation_display_id: conversation.display_id, status: 'created' }
  end

  def find_conversation(display_id)
    conversation = @account.conversations.find_by!(display_id: display_id)
    context = { user: @user, account: @account, account_user: @account_user }
    raise ActiveRecord::RecordNotFound unless ConversationPolicy.new(context, conversation).show?

    conversation
  end

  def contact_profile(email)
    contact = @account.contacts.find_by!(email: email.strip.downcase)
    recent = conversations.where(contact: contact).order(last_activity_at: :desc, id: :desc).limit(DEFAULT_RESULTS).to_a
    raise ActiveRecord::RecordNotFound if recent.empty? && !@account_user.administrator?

    contact.as_json(only: [:id, :name, :email, :custom_attributes]).merge(conversations: recent.map { |record| summary(record) })
  end

  def summary(conversation)
    conversation.as_json(only: [:display_id, :status, :last_activity_at])
  end
end
