require 'integration_helper'
require 'tmpdir'

RSpec.describe Bot::Helpers::Scheduler do
  around do |example|
    Dir.mktmpdir('velo-utro-scheduler-spec') do |directory|
      @temp_directory = directory
      example.run
    end
  end

  before do
    stub_const("#{described_class}::LOCK_FILE_PATH", File.join(@temp_directory, 'scheduler.lock'))
    stub_const("#{described_class}::LAST_ANNOUNCEMENT_PATH", File.join(@temp_directory, 'last-announcement'))
    stub_const("#{described_class}::LAST_MONTHLY_STATS_PATH", File.join(@temp_directory, 'last-monthly'))
  end

  after do
    described_class.stop
  end

  it 'starts the enabled daily announcement and monthly statistics jobs only once' do
    use_app_config(
      'DAILY_ANNOUNCEMENT_ENABLED' => true,
      'DAILY_ANNOUNCEMENT_TIME' => '18:30',
      'MONTHLY_STATS_DAY' => 5
    )
    bot, = recording_bot

    expect(described_class.start(bot)).to be(true)
    first_status = described_class.status
    expect(described_class.start(bot)).to be(true)
    second_status = described_class.status

    expect(first_status).to include(
      scheduler_running: true,
      daily_job_active: true,
      monthly_job_active: true,
      cron_expression: '30 18 * * * UTC',
      jobs_count: 2,
      lock_held: true
    )
    expect(first_status[:next_run]).not_to be_nil
    expect(second_status[:jobs_count]).to eq(2)
  end

  it 'starts with only the daily announcement configured' do
    use_app_config(
      'DAILY_ANNOUNCEMENT_ENABLED' => true,
      'DAILY_ANNOUNCEMENT_TIME' => '07:30',
      'MONTHLY_STATS_DAY' => nil
    )
    bot, = recording_bot

    expect(described_class.start(bot)).to be(true)
    expect(described_class.status).to include(
      scheduler_running: true,
      daily_job_active: true,
      monthly_job_active: false,
      cron_expression: '30 7 * * * UTC',
      jobs_count: 1,
      lock_held: true
    )
  end

  it 'starts only monthly statistics when daily announcements are disabled' do
    use_app_config('DAILY_ANNOUNCEMENT_ENABLED' => false, 'MONTHLY_STATS_DAY' => 5)
    bot, = recording_bot

    expect(described_class.start(bot)).to be(true)
    expect(described_class.status).to include(
      scheduler_running: true,
      daily_job_active: false,
      monthly_job_active: true,
      next_run: nil,
      cron_expression: nil,
      jobs_count: 1,
      lock_held: true
    )
  end

  it 'does not start when both scheduled features are disabled' do
    use_app_config('DAILY_ANNOUNCEMENT_ENABLED' => false, 'MONTHLY_STATS_DAY' => nil)
    bot, = recording_bot

    expect(described_class.start(bot)).to be(false)
    expect(described_class.status).to include(
      scheduler_running: false,
      daily_job_active: false,
      monthly_job_active: false,
      jobs_count: 0,
      lock_held: false
    )
  end

  it 'does not start while another process holds the scheduler lock' do
    use_app_config('MONTHLY_STATS_DAY' => 5)
    competing_lock = File.open(described_class::LOCK_FILE_PATH, File::RDWR | File::CREAT, 0o644)
    competing_lock.flock(File::LOCK_EX | File::LOCK_NB)
    bot, = recording_bot

    expect(described_class.start(bot)).to be(false)
    expect(described_class.status).to include(
      scheduler_running: false,
      monthly_job_active: false,
      jobs_count: 0,
      lock_held: false
    )
  ensure
    competing_lock&.flock(File::LOCK_UN)
    competing_lock&.close
  end

  it 'does not start when the scheduler lock file cannot be opened' do
    use_app_config('MONTHLY_STATS_DAY' => 5)
    stub_const("#{described_class}::LOCK_FILE_PATH", @temp_directory)
    bot, = recording_bot

    expect(described_class.start(bot)).to be(false)
    expect(described_class.status).to include(
      scheduler_running: false,
      monthly_job_active: false,
      jobs_count: 0,
      lock_held: false
    )
  end

  it 'sends monthly statistics once and records the completed period' do
    use_app_config(
      'MONTHLY_STATS_DAY' => 5,
      'PUBLIC_CHANNEL_ID' => '@veloutro'
    )
    AppClock.source = -> { Time.utc(2026, 8, 22, 9, 0) }
    bot, api = recording_bot

    first_result = described_class.send(:send_monthly_statistics, bot)
    second_result = described_class.send(:send_monthly_statistics, bot)

    expect(first_result).to be(true)
    expect(second_result).to be(false)
    expect(api.sent_messages).to contain_exactly(
      include(chat_id: '@veloutro', parse_mode: 'HTML')
    )
    expect(File.read(described_class::LAST_MONTHLY_STATS_PATH)).to eq('2026-7')
  end

  it 'announces only published events starting in the next 24 hours and records success once' do
    use_app_config(
      'DAILY_ANNOUNCEMENT_ENABLED' => true,
      'DAILY_ANNOUNCEMENT_TIME' => '18:30',
      'MONTHLY_STATS_DAY' => nil,
      'PUBLIC_CHANNEL_ID' => '@veloutro'
    )
    AppClock.source = -> { Time.utc(2026, 8, 23, 9, 0) }
    author = create_user(telegram_id: 301, username: 'Организатор')
    published = create_event(author: author, date: Date.new(2026, 8, 24), time: '09:00', published: true)
    create_event(author: author, date: Date.new(2026, 8, 24), time: '10:00', published: false)
    create_event(author: author, date: Date.new(2026, 8, 24), time: '12:01', published: true)
    bot, api = recording_bot
    described_class.start(bot)

    first_result = described_class.send(:send_daily_announcement, bot)
    second_result = described_class.send(:send_daily_announcement, bot)

    expect(first_result).to be(true)
    expect(second_result).to be(false)
    expect(api.sent_messages.map { |message| message[:text] }).to eq(
      [I18n.t('daily_announcement_header'), Bot::Helpers::Formatter.event_info(published)]
    )
    expect(File.read(described_class::LAST_ANNOUNCEMENT_PATH)).to eq(AppClock.utc_now.to_i.to_s)
    expect(described_class.status[:last_announcement_at]).to eq(AppClock.utc_now)
  end

  it 'announces that no events are scheduled in the next 24 hours' do
    use_app_config(
      'DAILY_ANNOUNCEMENT_ENABLED' => true,
      'MONTHLY_STATS_DAY' => nil,
      'PUBLIC_CHANNEL_ID' => '@veloutro'
    )
    bot, api = recording_bot
    described_class.start(bot)

    expect(described_class.send(:send_daily_announcement, bot)).to be(true)
    expect(api.sent_messages).to contain_exactly(
      include(
        chat_id: '@veloutro',
        text: I18n.t('daily_announcement_no_events'),
        parse_mode: 'HTML'
      )
    )
  end

  it 'does not record a daily announcement when Telegram delivery fails' do
    use_app_config(
      'DAILY_ANNOUNCEMENT_ENABLED' => true,
      'MONTHLY_STATS_DAY' => nil,
      'PUBLIC_CHANNEL_ID' => '@veloutro'
    )
    bot, = recording_bot(send_errors: [Faraday::TimeoutError.new('timeout')])
    described_class.start(bot)

    expect(described_class.send(:send_daily_announcement, bot)).to be(false)
    expect(File).not_to exist(described_class::LAST_ANNOUNCEMENT_PATH)
  end

  it 'does not record monthly statistics when Telegram delivery fails' do
    use_app_config(
      'MONTHLY_STATS_DAY' => 5,
      'PUBLIC_CHANNEL_ID' => '@veloutro'
    )
    AppClock.source = -> { Time.utc(2026, 8, 22, 9, 0) }
    bot, = recording_bot(send_errors: [Faraday::TimeoutError.new('timeout')])

    result = described_class.send(:send_monthly_statistics, bot)

    expect(result).to be(false)
    expect(File).not_to exist(described_class::LAST_MONTHLY_STATS_PATH)
  end

  it 'reports failure when the completed period cannot be recorded' do
    use_app_config(
      'MONTHLY_STATS_DAY' => 5,
      'PUBLIC_CHANNEL_ID' => '@veloutro'
    )
    AppClock.source = -> { Time.utc(2026, 8, 22, 9, 0) }
    non_directory = File.join(@temp_directory, 'not-a-directory')
    File.write(non_directory, 'occupied')
    stub_const(
      "#{described_class}::LAST_MONTHLY_STATS_PATH",
      File.join(non_directory, 'last-monthly')
    )
    bot, api = recording_bot

    result = described_class.send(:send_monthly_statistics, bot)

    expect(result).to be(false)
    expect(api.sent_messages).to contain_exactly(
      include(chat_id: '@veloutro', parse_mode: 'HTML')
    )
    expect(File).not_to exist(described_class::LAST_MONTHLY_STATS_PATH)
  end

  it 'releases its process lock on stop' do
    use_app_config('MONTHLY_STATS_DAY' => 5)
    bot, = recording_bot
    described_class.start(bot)

    described_class.stop
    competing_lock = File.open(described_class::LOCK_FILE_PATH, File::RDWR | File::CREAT, 0o644)

    expect(competing_lock.flock(File::LOCK_EX | File::LOCK_NB)).to be(0)
  ensure
    competing_lock&.close
  end
end
