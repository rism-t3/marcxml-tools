#!/usr/bin/env ruby
require 'rubygems'
require 'yaml'
require 'nokogiri'
require 'trollop'
require 'ruby-progressbar'
require 'rbconfig'
require 'zip'

OS=RbConfig::CONFIG['host_os']

#OPTIONS
opts = Trollop::options do
  version "RISM record_filter 1.0"
  banner <<-EOS
This utility program searches the complete RISM open data XML-File with parameters of query.yaml

Usage:
   record_search [options]
where [options] are:
  EOS

  opt :query, "Query-Filename", :type => :string, :default => "query.yaml"
  opt :connected, "Look for connected individual entries", :default=> false
  opt :debug, "Debugging mode", :default => false
  opt :infile, "Input-Filename", :type => :string
  opt :outfile, "Output-Filename", :type => :string, :default => "out.xml"
  opt :zip, "compress file with zip", :default => false
end
Trollop::die :infile, "must exist; you can download it from https://opac.rism.info/fileadmin/user_upload/lod/update/rismAllMARCXML.zip" if !opts[:infile]
source_file=opts[:infile]
resfile=opts[:outfile]

query=YAML.load_file(opts[:query])
print "\rCalculating total size..."
total=0
if OS =~ /linux/
  total =`grep -c "<record>" #{source_file}`.to_i
else
  file_size=File.size(source_file)
  if file_size > 800000000
    approx=3700
    total=(file_size / approx).floor
  else
    File.open( source_file, 'r:BINARY' ) do |io|
      io.each do |line| 
        total+=1 if line =~ /<record>/
      end
    end
  end
end

if opts[:connected]
  total=total * 2
end

connected_records=[]
result_records=[]
print "\rQuery: #{query}"

#Helper method to parse huge files with nokogiri
def each_record(filename, &block)
  File.open(filename) do |file|
    Nokogiri::XML::Reader.from_io(file).each do |node|
      if node.name == 'record' and node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT
        yield(Nokogiri::XML(node.outer_xml, nil, "UTF-8"))
      end
    end
  end
end

cnt=1
ofile=File.open(resfile, 'w')
ofile.write('<?xml version="1.0" encoding="UTF-8"?>'+"\n"+'<collection>'+"\n")
bar = ProgressBar.create(title: "Found", :format => "%c of %C Records checked. -- %a | %B | %p%% %e", total: total, remainder_mark: '-', progress_mark: '#')

#QUERY
each_record(source_file) do |record|
  result=[]
  id=record.xpath('//controlfield[@tag="001"]')[0].content 
  query.each do |k,v|
    if k.include?('$')
      df=k.split("$")[0]
      sf=k.split("$")[1]
      res=record.xpath('//datafield[@tag="'+df+'"]/subfield[@code="'+sf+'"]')
    else
      res=record.xpath('//controlfield[@tag="'+k+'"]')
    end
    res.each do |node|
      if v.class==String
        if node.content =~ /#{v}/
          result<<true
          break
        end
      elsif v.class==Array
        v.each do |entry|
          if node.content =~ /#{entry}/
            result<<true
          end
        end
      end
    end
  end
  cnt+=1
  if result.size==query.values.flatten.size
    if opts[:connected]
      record.xpath('//datafield[@tag="762"]/subfield[@code="w"]').each do |e|
        connected_records << e.content
      end
    end

    result_records << id
    n=Nokogiri::XML(record.to_s, &:noblanks)
    ofile.puts(n.root.to_xml :indent => 4)
  end
  bar.increment
end

if opts[:debug]
  d=File.open("recs", "w") do |f|
    f.write result_records.to_yaml
    f.write connected_records.to_yaml
  end
end
matched_individuals=0
individuals=[]
if opts[:connected]
  individuals=(connected_records - result_records).uniq
  each_record(source_file) do |record|
    id=record.xpath('//controlfield[@tag="001"]')[0].content 
    if individuals.include?(id)
      n=Nokogiri::XML(record.to_s, &:noblanks)
      ofile.puts(n.root.to_xml :indent => 4)
      matched_individuals+=1
    end
    bar.increment
  end
end

ofile.puts("</collection>")
ofile.close
puts ""
if opts[:zip]
  Zip::File.open(opts[:outfile].gsub(/.xml/, ".zip"), Zip::File::CREATE) do |zipfile|
        zipfile.add(opts[:outfile], opts[:outfile])
  end
end


puts "#{result_records.size+matched_individuals} Records found!"
