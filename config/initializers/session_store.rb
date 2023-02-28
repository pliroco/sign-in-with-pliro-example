Rails.application.config.session_store :active_record_store

ActiveRecord::SessionStore::Session.serializer = :null
