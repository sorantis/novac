require 'novadb'
require 'projects'
require 'json'

# required libs
required_libs = ['mysql']
begin
  required_libs.each { |l| require l }
rescue LoadError
  puts "This script needs the following external libraries: "
  required_libs.each { |l| puts " * #{l}" }
end

class Users

  attr_accessor :users
  def initialize
    novadb = NovaDB.new
    cloud = novadb.cloud
    @users = {}
    begin
      keystone = Mysql.new cloud[:server], cloud[:username], cloud[:password], 'keystone'

      # Get the id and name of all users
      user_rs = keystone.query "select id, name from user"
      user_rs.each_hash do |row|
        @users[row['id']] = row['name']
      end
    ensure
      keystone.close if keystone
    end
  end

  def user_names
    @users.values
  end

  def user_ids
    @users.keys
  end

  def list_user_roles(user_id)
    #If a user_id is specified (no nil) return just the one object, otherwiser assume all.

    #Validate user_id
    if user_id != nil && user_id != 'all' && @users[user_id] == nil
      puts 'Sorry. No such User ID (use UUID)'
      exit 1
    end

    if user_id == nil
      #Ignore User List: admin, swift, glance, cinder, nova and _member_
      #Flip user hash to retrieve ids
      inverted_users = @users.invert
      ignore_user_list = [inverted_users['admin'], inverted_users['swift'], inverted_users['glance'], inverted_users['cinder'], inverted_users['nova']]
      ignore_user_list_sql = ''
      ignore_user_list.each do |user|
        ignore_user_list_sql << " AND `user_id` != '#{user}'"
      end
    elsif user_id == 'all' || @users[user_id] != nil

    end

    ignore_role_list = [] # Create when reading the roles

    novadb = NovaDB.new
    cloud = novadb.cloud
    rows = []
    begin
      keystone = Mysql.new cloud[:server], cloud[:username], cloud[:password], 'keystone'

      projects = Projects.new
      @roles = {}

      role_rs = keystone.query "select id, name from role"
      role_rs.each_hash do |row|
          #Add _member_ id to ignore list
          if row['name'] == '_member_' && user_id == nil
            ignore_role_list << row['id']
          end
          @roles[row['id']] = row['name']
      end

      #SQL Query - no joins since we already have pulled the associated tables for other operations (users, projects, roles)
      if user_id == 'all'
        roles_rs = keystone.query "select user_id, project_id, data from user_project_metadata"
      elsif user_id != nil
        roles_rs = keystone.query "select user_id, project_id, data from user_project_metadata WHERE user_id = '#{user_id}'"
      else
        roles_rs = keystone.query "select user_id, project_id, data from user_project_metadata WHERE `user_id` != '0' #{ignore_user_list_sql}"
      end


      #Obtain User Role Information
      roles_rs.each_hash do |row|
        #Split up data section
        role_data = JSON.parse(row['data'])
        role_data["roles"].each do |role_row|
          next if user_id == nil && role_row == ignore_role_list[0]
          if not @roles[role_row]
            role = 'none'
          else
            role = @roles[role_row]
          end
          if not projects.projects[row['project_id']]
            project = 'none'
          else
            project = projects.projects[row['project_id']]
          end
          rows << [row['user_id'], @users[row['user_id']], project, role]
        end
      end

    ensure
      keystone.close if keystone
    end

    headings = ['ID', 'Username', 'Project/Tenant', 'Role']
    if user_id == 'all'
      rows = rows.sort_by {|e| e[3]}
      puts 'All users - sorted by Role'
    else
      rows = rows.sort_by {|e| [e[3],e[2]]}
      if user_id == nil
          puts 'Non Sysytem Users - sorted by Role, then Project'
      end
    end

    #Sort rows
    table = Terminal::Table.new :headings => headings, :rows => rows
    puts table
  end
end
