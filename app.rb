# The primary requirement of a Sinatra application is the sinatra gem.
require 'sinatra'
require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'net/http'
require 'net/https'
require 'thread'
require_relative 'httpHandler'
require_relative 'workers'

 
get '/' do
	erb :form
end

post '/search' do
	@keywords = params[:keywords]
	erb :search
end

get '/results' do

	  @companies_with_openings = @companies_with_openings.sort
	 erb :shows

end

# sinatra allows us to respond to route requests with code.  Here we are
# responding to requests for the root document - the naked domain.
post '/results' do
	#GENERATE REGEX BASED ON USER KEYWORDS
	keywords_array = params[:keywords].scan(/'.*?'|".*?"|\S+/)
	keywords_array.map!{|x| x.gsub(/\s+/," ").gsub(/[^\w\s]|_/, "")}
	keywords_regex = keywords_array.join("|")
	regex_job_title = /\b(#{keywords_regex})s?\b/i
	# SETUP ARRAYS
	nytmurls =[]
	nojobs = []
	careerlinksverified = []
	invalidids = []
	@companies_with_openings = {}

	#GET LAST PAGE OF COMPANIES
	 lastpage = Nokogiri::HTML(getResponse("https://nytm.org/made?list=true").body).at_css("div.digg_pagination > a:nth-last-child(2)").text.to_i

	 (1..lastpage).each do |id|

	  nytmurls << "https://nytm.org/made?list=true&page=#{id}"
	end

	#SET PROC TO GRAB COMPANY LINKS

	grabnynytmhiring = Proc.new do |z|
	  resp = getResponse(z)
	  if resp.code.match(/20\d/)
			Nokogiri::HTML(resp.body).css("a").select{|x| x.text == "Hiring"}.each do |y|
				if y['href'] =~ URI::regexp
				careerlinksverified << y['href']
				end
	       		# puts y['href']
	       	end
	  else
	    # puts "\tNot a valid page; response was: #{resp.code}"
	    invalidids << z
	  end
	end

	#GIVE WORKERS SOME WORK!

	useWorkers(nytmurls, grabnynytmhiring)


	#SAMPLE FILTER CRITERIA
	#regex_job_title = /\b(front ?\-?end|developer|automation|engineer|qa)s?\b/i

	#SET PROC TO LOOK FOR JOBS BASED ON CRITERIA
	grabjobs = Proc.new do |z|
	 begin
	  resp = getResponse(z)	
	  #   s = resp.code
	  # if ! s.valid_encoding?
	  # 	s = s.encode("UTF-16be", :invalid=>:replace, :replace=>"?").encode('UTF-8')
	  # end
	  if resp.code.match(/(2|3)0\d/)
	  	if !Nokogiri::HTML(resp.body).text.match(regex_job_title).nil?
			@companies_with_openings[z] = Nokogiri::HTML(resp.body).text.downcase.scan(regex_job_title)
		else
			nojobs << z
		end

	  else
	    # puts "\tNot a valid page; response was: #{resp.code} for site: #{url}" 
	    nojobs << z
	  end

	  rescue Exception => err
	  # p err
	  # p z
	  end
	 end

	 #GIVE WORKERS SOME MORE WORK!

	 useWorkers(careerlinksverified, grabjobs)
	 @companies_with_openings = @companies_with_openings.sort
	 
	  # this tells sinatra to render the Embedded Ruby template /views/shows.erb
	  erb :shows

end