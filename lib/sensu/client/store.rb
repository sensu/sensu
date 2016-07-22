require "sqlite3"

module Sensu
  module Client
    # Simple data store for the sensu client
    #
    # Although using something like Moneta seemed appealing, it does
    # not support iteration. I did not want to use redis either to avoid
    # requiring a separate process. There's then rlite which seems quite
    # interesting but immature, little docs, and not nearly as battle-tested
    # as sqlite. Finally, we have vedis, but little support for ruby
    # apparently, could not find usable bindings and in general it seems
    # our simple needs are achieved with sqlite.
    # May be at some point we should test the reliability of rlite and
    # use that if suitable, as it does seems nice.
    class Store
      def initialize(collection, logger)
        @db = SQLite3::Database.new('sensu-client.db')
        @collection = collection
        @logger = logger
        # We could use BLOB, but in sqlite everything is stored as text
        # anyways and using TEXT helps with debugging via sqlite cmdline
        # We use an id just because we can and helps sorting in order of
        # insertion and sqlite uses row ids internally anyways so it does
        # not need extra space.
        collection_sql = %{
          CREATE TABLE IF NOT EXISTS #{collection}(id INTEGER PRIMARY KEY AUTOINCREMENT, key TEXT UNIQUE NOT NULL, value TEXT)
        }
        begin
          @db.execute(collection_sql)
          return true
        rescue SQLite3::Exception
          @logger.error("Failed to initialize collection #{@collection}: #{$!}")
          return false
        end
      end

      def set(key, value)
        begin
          st = @db.prepare("REPLACE INTO #{@collection} (key, value) VALUES(?, ?)")
          st.execute(key, value).close
          return true
        rescue SQLite3::Exception
          @logger.error("Failed to set key #{key} to value #{value}: #{$!}")
          return false
        end
      end

      def get(key)
        begin
          rs = @db.prepare("SELECT value FROM #{@collection} WHERE key = ?").execute(key)
          r = rs.next
          rs.close
          if r
            return r[0]
          end
        rescue SQLite3::Exception
          @logger.error("Failed to get key #{key}: #{$!}")
        end
        return nil
      end

      def each
        return enum_for(:each) unless block_given?
        begin
          st = @db.prepare("SELECT key, value FROM #{@collection} ORDER BY id ASC")
          st.execute! do |row|
            yield row
          end
          st.close
        rescue SQLite3::Exception
          @logger.error("Failed to iterate over collection #{@collection}: #{$!}")
        end
      end

      def clear(limit_key=nil)
        begin
          query = "DELETE FROM #{@collection}"
          if limit_key.nil?
            @db.prepare(query).execute().close
          else
            query += " WHERE id <= (SELECT id FROM #{@collection} WHERE key = ?)"
            @db.prepare(query).execute(limit_key).close
          end
        rescue SQLite3::Exception
          @logger.error("Failed to clear collection #{@collection}: #{$!}")
        end
      end

      def length
        begin
          return @db.get_first_value("SELECT COUNT(*) FROM #{@collection}")
        rescue SQLite3::Exception
          @logger.error("Failed to get key #{key}: #{$!}")
        end
      end

      def close(drop=false)
        begin
          if drop
            @db.execute("DROP TABLE #{@collection}")
          end
          @db.close
          return true
        rescue SQLite3::Exception
          @logger.error("Failed to close db: #{$!}")
          return false
        end
      end
    end
  end
end
