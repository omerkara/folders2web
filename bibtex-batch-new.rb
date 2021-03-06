# encoding: UTF-8
$:.push(File.dirname($0))
require 'utility-functions'
require 'bibtex'
require 'citeproc'
require 'find'
require 'ap'

# batch processes entire bibliography file and generates ref:bibliography in wiki, used for refnotes database

##### utility functions

def debrace(str)
  str.gsub(/[\{\}]/,"")
end

def pdfpath(citekey)
  if File.exists?("#{PDF_path}/#{citekey.to_s}.pdf")
    return "[[skimx://#{citekey}|PDF]]"
  end
end

def sort_pubs(pubs)
  return pubs.sort {|x,y| x.to_s.scan(/[0-9]+/)[0].to_i <=> y.to_s.scan(/[0-9]+/)[0].to_i}
end

##### actions (not mutually dependent)

# saves the current file in BibDesk
def bibdesk_save
  require 'appscript'
  include Appscript
  dt = app('BibDesk')
  dt.document.save
end

# generates a new RSS feed by processing the pages queued in /wiki/rss-temp (which is generated by dokuwiki.rb add_to_rss
def make_rss_feed
  require 'rss/maker'
  fname = Wiki_path + "/rss-temp"
  rss_entries = Marshal::load(File.read(fname))

  version = "2.0" # ["0.9", "1.0", "2.0"]

  content = RSS::Maker.make(version) do |m|
    m.channel.title = Wiki_title
    m.channel.link = Internet_path
    m.channel.description = Wiki_desc
    m.items.do_sort = true # sort items by date
  
    rss_entries.each do |entry|
      i = m.items.new_item
      i.title = entry[:title]
      i.link = entry[:link]
      i.date = entry[:date]
      i.description = entry[:description]
    end
  end

  File.write(Wiki_path + "/data/media/pages.xml", content) 
end

# take an array of publications of the BibTex class, sort, and create an HTML list
def generate_pub_list(publications)
  # sorting bibliography, first on how many files (notes etc), and then on citekey
  # it's weird [0][1] because in the sort above, it gets transformed first to a hash and then to an array. don't ask me :)
  # this way of trying to sort on two different criteria is not perfect, but mostly works
  
  # make hash if bibtex, if array leave alone, this allows for sorting
  pubs = publications.class == BibTeX::Bibliography ? publications.to_hash.sort[0][1] : publications

  pubsort = pubs.sort do |x,y| 
    if debrace(y[:hasfiles]).to_s.strip.size == debrace(x[:hasfiles]).to_s.strip.size
      x[:key].to_s <=> y[:key].to_s
    else
      debrace(y[:hasfiles]).to_s <=> debrace(x[:hasfiles]).to_s
    end
  end

  # adding each item to the HTML output, properly formatted
  outcit = ''
  pubsort.each do |item|      
    link = item[:hasfiles].to_s.index("H") ? "<a href = '/wiki/ref:#{item[:key]}'>" : ""   # only link if ref exists
    outcit << "<tr><td>#{link}#{item[:key]}</a></td><td>#{debrace(item[:hasfiles]).split("").join("</td><td>&nbsp;")}</td><td>#{debrace(item[:cit])}</td></tr>\n"
  end
  return outcit
end


# executing actions
# bibdesk_save
# make_rss_feed

#################################################

f_to_check = {
  :notes => ["notes"],
  :clippings => ["clip", "kindle"],
  :images => ["skimg"],
  :hasref => ["ref"]
}

publications = BibTeX.open("bibliography-short.bib")   # !!using a smaller pub file for more rapid testing
publications.parse_names

author_pubs, json, keywords, counter, category = Hash.new, Hash.new, Hash.new, Hash.new, Hash.new
json = Hash.new

publications.each do |item|

  # if the publication has one or more authors, add the publication to each author's hash, and add each authors'
  # last name to the list of
  pub_authors = []
  if item.respond_to? :author
    item.author.each do |a|                 # for each author of the publication
      pub_authors << debrace(a.last)      # add the last name without BibTex artefacts to the pub_authors array (for use)
                                          # in generating json citation
      author_pubs.add(nice_name(a), item) # add it to the author index (for abib:)
    end
  end

  # add item to the keyword index if it has a keyword
  item.keywords.split(";").each { |a| keywords.add(a.strip, item) } if item.respond_to? :keywords

  # render APA citation of publication
  item.cit = CiteProc.process item.to_citeproc, :style => :apa

  # make nice year for in-text citation
  year = (defined? item.year) ? item.year.to_s : "n.d."       # try to get the year from the bibtex entry
  year = $1 if year == "n.d." and item.cit.to_s.match(/\((....)\)/)     # if not, try to get it from the generated APA citation

  # add json entry for this publication, with author string, year, and full citation
  json[item.key.to_s] = [namify(pub_authors), year, item.cit.to_s]

  # check the paths listed in f_to_check, increment global counters, and store values for bibliography printout
  hasfiles = ""
  f_to_check.each do |kind, dirs|
    if (dirs.each {|f| break(true) if File.exists?("#{Wikipages_path}/#{f}/#{item.key.to_s}.txt")})==true        
      counter.add(kind, 1)                                   # increment the global counter
      hasfiles << kind[0,1].upcase                           # add letter string
    else
      hasfiles << " "
    end
  end
  item.hasfiles = hasfiles                                    # store letter string

end

outcit = generate_pub_list(publications)

stats = "Statistics: Totally **#{publications.size}** publications, and **#{counter[:hasref]}** publications have their own wikipages **(H)**. Of these, **#{counter[:notes]}** with notes (key ideas) **(N)**, **#{counter[:clippings]}** with highlights (imported from Kindle or Skim) **(C)**, and **#{counter[:images]}** with images (imported from Skim) **(I)**.<html><table>\n\n"
out = Bibliography_header << stats << outcit << "</table></html>"   # combining the various texts and generated bibliography

File.write("#{Wikipages_path}/bib/bibliography.txt", out)           # write HTML bibliography (using HTML because DW cannot
                                                                    # render table with a thousand rows)
                                                                    
File.write(JSON_path, JSON.fast_generate(json) )                    # generating JSON file

authorlisted = Array.new
author_pubs.each do |author, pubs|
  
  # only generates individual author pages for authors with full names. this is because I want to deduplicate author names
  # when you import bibtex, you get many different spellings etc. 
  next if (author.strip[-1] == "." || author[-2] == " " || author[-2] == author[-2].upcase || author[1] == '.')
  puts author
  out = "h2. #{author}'s publications\n\n<html>\n<table>\n"

  out << generate_pub_list(pubs) << "</table></html>"              # add sorted list of that author's publications

  authorname = clean_pagename(author)
  authorlisted << [authorname,author,pubs.size]
  File.write("#{Wikipages_path}/abib/#{authorname}.txt", out)
end


exit(0)

# File.open("#{Wikipages_path}/abib/start.txt","w") do |f|
#   f << "h1.List of authors with publications\n\nList of authors with publications. Only includes authors with three or more publications, with full names.\n\n"
#   authorlisted.sort {|x,y| y[2].to_i <=> x[2].to_i}.each do |ax|
#     apage = ''
#     if File.exists?("#{Wikipages_path}/a/#{ax[0]}.txt")
#       apage = "[[:a:#{ax[0]}|author page]]"
#     end
#     f << "| [[#{ax[0]}|#{ax[1]}]] | #{apage} |#{ax[2]}|\n"
#   end
# end