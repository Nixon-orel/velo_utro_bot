# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 10) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "events", force: :cascade do |t|
    t.date "date", null: false
    t.string "time", null: false
    t.string "event_type", null: false
    t.string "location", null: false
    t.string "distance"
    t.string "pace"
    t.text "additional_info"
    t.bigint "author_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "track"
    t.string "map"
    t.integer "channel_message_id"
    t.jsonb "weather_data"
    t.jsonb "weather_history", default: []
    t.datetime "weather_updated_at"
    t.jsonb "weather_alerts_sent", default: {}
    t.string "weather_city"
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.boolean "published", default: false, null: false
    t.datetime "published_at"
    t.integer "weather_schedule_revision", default: 0, null: false
    t.index ["author_id"], name: "index_events_on_author_id"
    t.check_constraint "weather_schedule_revision >= 0", name: "events_weather_schedule_revision_check"
  end

  create_table "notification_deliveries", force: :cascade do |t|
    t.bigint "event_id", null: false
    t.bigint "recipient_id"
    t.string "notification_type", null: false
    t.string "context_key", null: false
    t.string "idempotency_key", null: false
    t.string "operation", default: "send_message", null: false
    t.string "chat_id", null: false
    t.jsonb "payload", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.integer "attempts", default: 0, null: false
    t.datetime "next_attempt_at"
    t.datetime "locked_at"
    t.string "lock_token"
    t.datetime "delivered_at"
    t.text "last_error"
    t.jsonb "error_history", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "finalized_at"
    t.index ["event_id"], name: "index_notification_deliveries_on_event_id"
    t.index ["idempotency_key"], name: "index_notification_deliveries_on_idempotency_key", unique: true
    t.index ["locked_at"], name: "index_notification_deliveries_on_locked_at", where: "((status)::text = 'processing'::text)"
    t.index ["notification_type", "id"], name: "index_notification_deliveries_unfinalized", where: "(((status)::text = 'delivered'::text) AND (finalized_at IS NULL))"
    t.index ["recipient_id"], name: "index_notification_deliveries_on_recipient_id"
    t.index ["status", "next_attempt_at"], name: "index_notification_deliveries_on_status_and_next_attempt_at"
    t.check_constraint "attempts >= 0", name: "notification_deliveries_attempts_check"
    t.check_constraint "finalized_at IS NULL OR status::text = 'delivered'::text", name: "notification_deliveries_finalized_at_check"
    t.check_constraint "jsonb_typeof(error_history) = 'array'::text", name: "notification_deliveries_error_history_check"
    t.check_constraint "jsonb_typeof(payload) = 'object'::text", name: "notification_deliveries_payload_check"
    t.check_constraint "operation::text = ANY (ARRAY['send_message'::character varying, 'edit_message_text'::character varying]::text[])", name: "notification_deliveries_operation_check"
    t.check_constraint "status::text = 'pending'::text AND next_attempt_at IS NOT NULL AND locked_at IS NULL AND lock_token IS NULL AND delivered_at IS NULL OR status::text = 'processing'::text AND locked_at IS NOT NULL AND lock_token IS NOT NULL AND delivered_at IS NULL OR status::text = 'delivered'::text AND next_attempt_at IS NULL AND locked_at IS NULL AND lock_token IS NULL AND delivered_at IS NOT NULL OR (status::text = ANY (ARRAY['failed'::character varying, 'cancelled'::character varying]::text[])) AND next_attempt_at IS NULL AND locked_at IS NULL AND lock_token IS NULL AND delivered_at IS NULL", name: "notification_deliveries_state_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'processing'::character varying, 'delivered'::character varying, 'failed'::character varying, 'cancelled'::character varying]::text[])", name: "notification_deliveries_status_check"
  end

  create_table "participants", force: :cascade do |t|
    t.bigint "event_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "user_id"], name: "index_participants_on_event_id_and_user_id", unique: true
    t.index ["event_id"], name: "index_participants_on_event_id"
    t.index ["user_id"], name: "index_participants_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.string "user_id", null: false
    t.text "data"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "nickname"
    t.string "username", null: false
    t.string "telegram_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "subscribed_to_notifications", default: false, null: false
    t.index ["telegram_id"], name: "index_users_on_telegram_id", unique: true
  end

  add_foreign_key "events", "users", column: "author_id"
  add_foreign_key "notification_deliveries", "events", on_delete: :cascade
  add_foreign_key "notification_deliveries", "users", column: "recipient_id", on_delete: :nullify
  add_foreign_key "participants", "events"
  add_foreign_key "participants", "users"
end
