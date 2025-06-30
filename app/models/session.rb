class Session < ActiveRecord::Base
  validates :user_id, presence: true, uniqueness: true
  
  serialize :data, coder: JSON
  
  def [](key)
    data_hash = data.is_a?(Hash) ? data : {}
    data_hash[key.to_s]
  end
  
  def []=(key, value)
    data_hash = data.is_a?(Hash) ? data : {}
    data_hash[key.to_s] = value
    self.data = data_hash
  end
  
  def state
    self['state']
  end
  
  def state=(value)
    self['state'] = value
  end
  
  def new_event
    self['new_event'] || {}
  end
  
  def new_event=(value)
    self['new_event'] = value
  end
  
  def calendar_type
    self['calendar_type']
  end
  
  def calendar_type=(value)
    self['calendar_type'] = value
  end
  
  def edit_event_id
    self['edit_event_id']
  end
  
  def edit_event_id=(value)
    self['edit_event_id'] = value
  end
  
  def self.load(user_id)
    find_or_create_by(user_id: user_id) do |session|
      session.data = {}
    end
  end
  
  def save_session
    save
  end
end