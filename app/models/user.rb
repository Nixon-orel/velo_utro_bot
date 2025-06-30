class User < ActiveRecord::Base
  has_many :authored_events, class_name: 'Event', foreign_key: 'author_id'
  has_and_belongs_to_many :events_as_participant, 
                          class_name: 'Event', 
                          join_table: 'participants',
                          foreign_key: 'user_id',
                          association_foreign_key: 'event_id'
  
  validates :telegram_id, presence: true, uniqueness: true
  validates :username, presence: true
  
  def self.find_or_create_from_telegram(telegram_user)
    user = find_by(telegram_id: telegram_user.id.to_s)
    
    if user
      if user.username != telegram_user.first_name || user.nickname != telegram_user.username
        user.update(
          username: telegram_user.first_name,
          nickname: telegram_user.username
        )
      end
    else
      user = create(
        telegram_id: telegram_user.id.to_s,
        username: telegram_user.first_name,
        nickname: telegram_user.username
      )
    end
    
    user
  end
  
  def admin?
    admin_ids = ENV['ADMIN_IDS'].to_s.split(',').map(&:strip)
    admin_ids.include?(telegram_id)
  end
  
  def display_name
    nickname.present? ? "@#{nickname}" : username
  end
end