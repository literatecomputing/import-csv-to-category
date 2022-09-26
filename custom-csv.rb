# frozen_string_literal: true

require "csv"
require File.expand_path(File.dirname(__FILE__) + "/base.rb")

# Edit the constants and initialize method for your import data.

class ImportScripts::CsvRestoreStagedUsers < ImportScripts::Base

  CSV_FILE_PATH = ENV['CSV_FILE_PATH'] || "missing"
  TARGET_CATEGORY = ENV['TARGET_CATEGORY'] || "General"
  DELETE_TARGET_CAT = true # delete all topics from target category so this can be re-run on top of existing data

  puts "the file #{CSV_FILE_PATH}"

  BATCH_SIZE ||= 1000

  def initialize
    category = Category.find_by_name(TARGET_CATEGORY)

    if category
      puts "found #{category.name}"
    else
      puts "Cannot find #{TARGET_CATEGORY}. Giving up."
      exit
    end

    if DELETE_TARGET_CAT
      puts "deleting from #{category.name}"
      Topic.where(category_id: category.id).destroy_all
      puts "deleting post custom fields"
      PostCustomField.where(name: 'import_id').destroy_all
      puts "deleted"
    end


    super

    @imported_topics = load_csv(CSV_FILE_PATH)
    @skip_updates = true

  end

  def execute
    puts "", "Importing from CSV file..."

    import_topics

    puts "", "Done"
  end

  def load_csv(path)
    CSV.parse(File.read(path), liberal_parsing: true, headers: false)
  end

  def username_for(name)
    result = name.downcase.gsub(/[^a-z0-9\-\_]/, '')

    if result.blank?
      result = Digest::SHA1.hexdigest(name)[0...10]
    end

    result
  end

  def get_email(id)
    email = nil
    @imported_emails.each do |e|
      if e["user_id"] == id
        email = e["email"]
      end
    end
    email
  end

  def get_custom_fields(id)
    custom_fields = {}
    @imported_custom_fields.each do |cf|
      if cf["user_id"] == id
        custom_fields[cf["name"]] = cf["value"]
      end
    end
    custom_fields
  end

  def import_users
    puts '', "Importing users"

    users = []
    @imported_users.each do |u|
      email = get_email(u['id'])
      custom_fields = get_custom_fields(u['id'])
      u['email'] = email
      u['custom_fields'] = custom_fields
      users << u
    end
    users.uniq!

    create_users(users) do |u|
      {
        id: u['email'],
        username: u['username'],
        email: u['email'],
        created_at: u['created_at'],
        staged: u['staged'],
        custom_fields: u['custom_fields'],
      }
    end
  end

  def import_topics
    puts '', "Importing topics"

    category = Category.find_by_name(TARGET_CATEGORY)
    topics = []

    puts "Topic lines: #{@imported_topics.count}"
    head1 = @imported_topics[1]
    head2 = @imported_topics[2]
    head3 = @imported_topics[3]
    head4 = @imported_topics[4]
    head5 = @imported_topics[5]
    id = 6
    @imported_topics[6..].each do |t|
      rec = {}
      if t[0]
        t[0]=t[0].strip
        user = User.find_by_email(t[0])
        unless user
          u = {}
          u[:email]=t[0]
          u[:id] = id
          u[:username] = t[0]
          create_user(u,id)
          user = User.find_by_email(t[0])
          user = Discourse.system_user unless user
          puts "created #{user.username}"
        end
      else
        user = Discourse.system_user unless user
      end

      rec['id'] = id
      rec['user_id'] = user.id
      rec['title'] = t[1] || "missing title for row #{id}"
      rec['category'] = category.id
      rec['raw'] = make_raw_from_rows(head1, head2, head3, head4, head5, t)
      topics.append (rec)
      id += 1
    end

    puts "creating #{topics.count} topics"

    create_posts(topics) do |p|
      {
          id: p['id'],
          user_id: p['user_id'],
          title: p['title'],
          category: p['category'],
          raw: p['raw'],
      }
    end
  end

  def make_raw_from_rows(head1, head2, head3, head4, head5, row)
    column = 0
    raw = ""
    for x in 2..row.length
      raw += "# #{head1[x]}\n" if head1[x] && row[x]
      raw += "## #{head2[x]}\n" if head2[x] && row[x]
      raw += "### #{head3[x]}\n" if head3[x] && row[x]
      raw += "#### #{head4[x]}\n" if head4[x] && row[x]
      raw += "##### #{head5[x]}\n" if head5[x] && row[x]
      raw += "#{row[x]}\n" if row[x]
    end
    raw
  end

end



if __FILE__ == $0
  ImportScripts::CsvRestoreStagedUsers.new.perform
end
