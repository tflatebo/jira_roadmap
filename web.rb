require 'bundler/setup'
require 'sinatra'
require 'net/https'
require 'json'
require 'haml'
require 'sinatra/config_file'

config_file 'config/config.yml'

# add in basic auth using env variables
helpers do
  def protected!
    return if authorized?
    headers['WWW-Authenticate'] = 'Basic realm="Restricted Area"'
    halt 401, "Not authorized\n"
  end

  def authorized?
    @auth ||=  Rack::Auth::Basic::Request.new(request.env)
    @auth.provided? and @auth.basic? and @auth.credentials and @auth.credentials == [ENV['ADMIN_USER'], ENV['ADMIN_PASS']]
  end
end

get '/' do
  protected!

  @grouping = params["group"]? params["group"] : "roadmap_group"

  @jiras = get_roadmap 
  @r_items = []

  @jiras['issues'].each {|jira| 
    @r_item = {}

    if(jira['fields'])
      
      #puts 'JIRA: ' + jira.to_s
      # "priority"=>{"self"=>"https://govdelivery.atlassian.net/rest/api/2/priority/4", "iconUrl"=>"https://govdelivery.atlassian.net/images/icons/priorities/minor.png", "name"=>"Medium", "id"=>"4"}
      if jira['fields']['customfield_12151'].nil?
        roadmap_group = "Unset"
      else
      	roadmap_group = jira['fields']['customfield_12151']['value']
      end

      if jira['fields']['customfield_11850'].nil?
        scrum_team = "Unset"
      else
      	scrum_team = jira['fields']['customfield_11850']['value']
      end

      if jira['fields']['customfield_10003'].nil?
        points = 0;
      else
      	points = jira['fields']['customfield_10003']
      end

      @r_item['content'] = jira['fields']['summary']
      @r_item['start'] = Time.parse(jira['fields']['customfield_11950'])
      @r_item['end'] = Time.parse(jira['fields']['customfield_11951'])
      @r_item['scrum_team'] = scrum_team
      @r_item['jira_uri'] = 'https://' + settings.jira_host + '/browse/' + jira['key']
      @r_item['jira_description'] = jira['renderedFields']['description']
      @r_item['scrum_team_css'] = cssify(scrum_team)
      @r_item['jira_key'] = jira['key']
      @r_item['source'] = roadmap_group
      @r_item['points'] = points
      @r_item['priority'] = jira['fields']['priority']['name']
      @r_item['priorityImage'] = jira['fields']['priority']['iconUrl']

      if @grouping.eql? "scrum_team"
        @r_item['group'] = scrum_team 
      else
        @r_item['group'] = roadmap_group
      end

      @r_items.push(@r_item)
    end
  }

  haml :index, :locals => {:jiras => @r_items}
end

def cssify(input)
  input = input.tr( '^A-Za-z', '' )
  input = input.tr( 'A-Z', 'a-z' )

  return input
end

get '/roadmap' do
  protected!
  return JSON.pretty_generate(get_roadmap)
end

def get_roadmap

  @jira_epics = ''

  http = Net::HTTP.new(settings.jira_host, settings.jira_port)
  http.use_ssl = settings.use_ssl
  http.start do |http|
    req = Net::HTTP::Get.new(settings.jira_path)

    # we make an HTTP basic auth by passing the
    # username and password
    req.basic_auth ENV['JIRA_USER'], ENV['JIRA_PASS']
    resp, data = http.request(req)
    #print "Resp: " + resp.code.to_s + "\n"
    #print "Data: " +  JSON.pretty_generate(JSON.parse(resp.body.to_s))

    @jira_epics = JSON.parse(resp.body.to_s)
  end

  return @jira_epics
end
