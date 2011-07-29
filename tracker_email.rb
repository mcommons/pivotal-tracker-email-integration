#!/usr/local/bin/ruby
require 'rubygems'
require 'pivotal_tracker'
require 'net/smtp' #for outgoing response

# YOU MUST CHANGE THESE VALUES TO MATCH YOUR PROJECT!
TRACKER_PROJECT_ID = 000000
TRACKER_API_TOKEN = 'du2i3hd2iuiuye8i'

# keeps only the first mime part
def read_email_from_sdtin
  email = ''
  chunk_start = '--no-chunk--'
  $stdin.each_line do |line|
    break if line == chunk_start
    unless line.match(/^--\S*$/).nil?
      chunk_start = line
    end
    email << line
  end
  email
end

# eliminate the fwd and re in the subject
def parse_subject(email)
  email.scan(/Subject: (?:Fwd:\s*)?(?:Re:\s*)?(.*)/).flatten.first
end

def parse_to(email)
  email.scan(/To: (.*)/).flatten.first
end

def parse_cc_name(email)
  cc = email.scan(/Cc: \"(.*)\"/).flatten.first || email.scan(/Cc: (.*) \</).flatten.first
  cc.gsub(/[\"\\]/,'') if cc
end

def parse_body(email)
  email.scan(/[\r|\n]{2}(.*)/m).join 
end

# This will regex the name from the following formats so far:
# From: "Benjamin Stein" <ben@mcommons.com>
# From: Benjamin Stein <ben@mcommons.com>
def parse_name(email)
  email.scan(/From: \"(.*)\"/).flatten.first || email.scan(/From: (.*) \</).flatten.first
end
def parse_from(email)
  email.scan(/From: (.*)/).flatten.first
end

def get_story_type_from_email_address(address)
  case address
  when /feature/ then :feature
  when /bug/     then :bug
  when /chore/   then :chore
  else                :feature
  end
end

def send_confirmation_email(from, to, subject, message)
  msg = <<END_OF_MESSAGE
From: #{from} <#{from}>
To: #{to} <#{to}>
Subject: #{subject}

#{message}
END_OF_MESSAGE

  Net::SMTP.start('localhost') do |smtp|
    smtp.send_message msg, from, to
  end  
end



email = read_email_from_sdtin

subject   = parse_subject(email)
to        = parse_to(email)
body      = parse_body(email)
from      = parse_from(email)
from_name = parse_name(email)
cc_name   = parse_cc_name(email)

# Tracker has a max_len for description and comments
# Split up the email body into chunks; use the first one as the description
# and the remainder as comments
chunks = body.split(/(.{5000})/m).reject{|token| token.nil? || token.length==0}
description = chunks[0]
comments    = chunks[1..-1] || []
PivotalTracker::Client.token = TRACKER_API_TOKEN 
project = PivotalTracker::Project.find(TRACKER_PROJECT_ID) 

story   = {
  :story_type   => get_story_type_from_email_address(to),
  :description  => description,
  :name         => subject,
  :requested_by => from_name
}
story[:owned_by] = cc_name if cc_name
created_story = project.stories.create(story)

#now update the story N times with each comment
comments.each do |comment|
  created_story.notes.create(:text => comment)
end

send_confirmation_email(to, from, "Successfully Created Story #{created_story.id}!", created_story.inspect) 
