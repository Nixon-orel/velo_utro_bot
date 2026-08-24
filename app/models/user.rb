class User < ActiveRecord::Base
  has_many :authored_events, class_name: 'Event', foreign_key: 'author_id'
  has_many :notification_deliveries, foreign_key: 'recipient_id', dependent: :nullify
  has_and_belongs_to_many :events_as_participant, 
                          class_name: 'Event', 
                          join_table: 'participants',
                          foreign_key: 'user_id',
                          association_foreign_key: 'event_id'
  
  validates :telegram_id, presence: true
  
  def self.find_or_create_from_telegram(telegram_user)
    telegram_id = telegram_user.id.to_s
    username = telegram_user.first_name.presence || "Пользователь"
    nickname = telegram_user.username

    user = create_or_find_by!(telegram_id: telegram_id) do |new_user|
      new_user.username = username
      new_user.nickname = nickname
    end

    if user.username != username || user.nickname != nickname
      user.update!(username: username, nickname: nickname)
    end

    user
  end
  
  def admin?
    APP_CONFIG.admin_ids.include?(telegram_id)
  end
  
  def display_name
    if nickname.present?
      "@#{nickname}"
    elsif username.present? && username != "Пользователь"
      username
    else
      "Пользователь #{telegram_id[-4..-1]}"
    end
  end
end
