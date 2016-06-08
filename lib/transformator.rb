# encoding: UTF-8
require 'rubygems'
require 'nokogiri'
require 'rbconfig'
require_relative 'logging'

class Transformator
  include Logging
  attr_accessor :node, :namespace, :connection
  def initialize(node, namespace={'marc' => "http://www.loc.gov/MARC21/slim"})
    @namespace = namespace
    @node = node
  end


  def rename_subfield_code(tag, old_code, new_code)
    subfield=node.xpath("//marc:datafield[@tag='#{tag}']/marc:subfield[@code='#{old_code}']", NAMESPACE)
    if !subfield.empty? && !node.xpath("//marc:datafield[@tag='#{tag}']/marc:subfield[@code='#{new_code}']", NAMESPACE).empty?
      puts "WARNING: #{tag}$#{new_code} already exits!"
    end
    subfield.attr('code', new_code) if subfield
    subfield
  end

  def change_content(tag, code, replacements)
    nodes=node.xpath("//marc:datafield[@tag='#{tag}']/marc:subfield[@code='#{code}']", NAMESPACE)
    nodes.each do |n|
      if replacements[n.text]
        n.content = replacements[n.text]
      end
    end
    nodes
  end

  def move_subfield_to_tag(from_tag, tag)
    ftag=from_tag.split("$")[0]
    fcode=from_tag.split("$")[1]
    target=node.xpath("//marc:datafield[@tag='#{tag}']", NAMESPACE)
    source=node.xpath("//marc:datafield[@tag='#{ftag}']/marc:subfield[@code='#{fcode}']", NAMESPACE)
    if target.empty?
      rename_datafield(ftag, tag) 
    else
      target.children.first.add_previous_sibling(source)
    end
    if node.xpath("//marc:datafield[@tag='#{ftag}']/marc:subfield[@code='*']", NAMESPACE).empty?
      node.xpath("//marc:datafield[@tag='#{ftag}']", NAMESPACE).remove
    end
    target
  end

  def remove_subfield(ftag)
    tag=ftag.split("$")[0]
    code=ftag.split("$")[1]
    node.xpath("//marc:datafield[@tag='#{tag}']/marc:subfield[@code='#{code}']", NAMESPACE).remove
  end

  def remove_datafield(tag)
    node.xpath("//marc:datafield[@tag='#{tag}']", NAMESPACE).remove
  end


  def check_material
    result = Hash.new
    subfield=node.xpath("//marc:datafield[@tag='100']/marc:subfield[@code='a']", NAMESPACE)
    if subfield.text=='Collection'
      result[:level] = "c"
    else
      result[:level] = "m"
    end
    subfield=node.xpath("//marc:datafield[@tag='762']", NAMESPACE)
    unless subfield.empty?
      result[:level] = "c"
    end

    subfield=node.xpath("//marc:datafield[@tag='773']", NAMESPACE)
    unless subfield.empty?
      result[:level] = "d"
    end

    subfields=node.xpath("//marc:datafield[@tag='593']/marc:subfield[@code='a']", NAMESPACE)
    material = []
    subfields.each do |sf|
      if (sf.text =~ /manusc/) || (sf.text =~ /autog/)
        material << :manuscript
      elsif sf.text =~ /print/
        material << :print
      else
        material << :other
      end
    end
    case
    when material.include?(:manuscript) && material.include?(:print)
      result[:type] = "p"
    when material.include?(:manuscript) && !material.include?(:print)
      result[:type] = "d"
    else
      result[:type] = "c"
    end
    return result
  end

  def change_leader
    leader=node.xpath("//marc:leader", NAMESPACE)[0]
    result=check_material
    code = "n#{result[:type]}#{result[:level]}"
    raise "Leader code #{code} false" unless code.size == 3
    if leader
      leader.content="00000#{code} a2200000   4500"
    else
      leader = Nokogiri::XML::Node.new "leader", node
      leader.content="00000#{code} a2200000   4500"
      node.root.children.first.add_previous_sibling(leader)
    end
    leader
  end

  def rename_datafield(tag, new_tag)
    if !node.xpath("//marc:datafield[@tag='#{new_tag}']", NAMESPACE).empty?
      puts "WARNING: Tag #{new_tag} already exits!"
    end
    datafield=node.xpath("//marc:datafield[@tag='#{tag}']", NAMESPACE)
    datafield.attr('tag', new_tag) if datafield
    datafield
  end

  def change_collection
    subfield=node.xpath("//marc:datafield[@tag='100']/marc:subfield[@code='a']", NAMESPACE)
    if subfield.text=='Collection'
      node.xpath("//marc:datafield[@tag='100']", NAMESPACE).remove
      rename_datafield('240', '130')
    end
  end

  def delete_anonymus
    subfield=node.xpath("//marc:datafield[@tag='100']/marc:subfield[@code='a']", NAMESPACE)
    if subfield.text=='Anonymus'
      node.xpath("//marc:datafield[@tag='100']", NAMESPACE).remove
    end
  end

  def change_material
    materials=node.xpath("//marc:datafield/marc:subfield[@code='8']", NAMESPACE)
    materials.each do |material|
      begin
        material.content="%02d" % material.content.gsub("\\c", "") if material
      rescue ArgumentError
      end
    end
  end

  def zr_addition_change_scoring
    scoring = node.xpath("//marc:datafield[@tag='594']/marc:subfield[@code='a']", NAMESPACE)
    scoring.each do |tag|
      entries = tag.content.split(/,(?=\s\D)/)
      entries.each do |entry|
        instr = entry.split("(").first
        amount = entry.gsub(/.+\((\w+)\)/, '\1')
        tag = Nokogiri::XML::Node.new "datafield", node
        tag['tag'] = '594'
        tag['ind1'] = ' '
        tag['ind2'] = ' '
        sfa = Nokogiri::XML::Node.new "subfield", node
        sfa['code'] = 'b'
        sfa.content = instr.strip
        sf2 = Nokogiri::XML::Node.new "subfield", node
        sf2['code'] = 'c'
        sf2.content = amount==instr ? 1 : amount
        tag << sfa << sf2
        node.root << tag
      end
    end
    #rnode = node.xpath("//marc:datafield[@tag='594']", NAMESPACE).first
    #rnode.remove if rnode
  end




  def zr_addition_change_attribution
    subfield100=node.xpath("//marc:datafield[@tag='100']/marc:subfield[@code='j']", NAMESPACE)
    subfield700=node.xpath("//marc:datafield[@tag='700']/marc:subfield[@code='j']", NAMESPACE)
    subfield710=node.xpath("//marc:datafield[@tag='710']/marc:subfield[@code='g']", NAMESPACE)
    subfield100.each { |sf| sf.content = convert_attribution(sf.content) }
    subfield700.each { |sf| sf.content = convert_attribution(sf.content) }
    subfield710.each { |sf| sf.content = convert_attribution(sf.content) }
  end

  def zr_addition_change_593_abbreviation
    subfield=node.xpath("//marc:datafield[@tag='593']/marc:subfield[@code='a']", NAMESPACE)
    subfield.each { |sf| sf.content = convert_593_abbreviation(sf.content) }
  end

  def zr_addition_change_gender
    subfield=node.xpath("//marc:datafield[@tag='039']/marc:subfield[@code='a']", NAMESPACE)
    subfield.each { |sf| sf.content = convert_gender(sf.content) }
  end

  def zr_addition_change_individualize
    subfield=node.xpath("//marc:datafield[@tag='042']/marc:subfield[@code='a']", NAMESPACE)
    subfield.each { |sf| sf.content = convert_individualize(sf.content) }
  end

  def zr_addition_catalogue_change_media
    subfield=node.xpath("//marc:datafield[@tag='337']/marc:subfield[@code='a']", NAMESPACE)
    subfield.each { |sf| sf.content = convert_media(sf.content) }
  end

  def zr_addition_change_035
    refs = []
    subfields=node.xpath("//marc:datafield[@tag='035']/marc:subfield[@code='a']", NAMESPACE)
    subfields.each do |sf|
      if sf.content =~ /; /
        content = sf.content.gsub("(DE-588a)(VIAF)", "(VIAF)")
        content.split("; ").each do |e|
          refs << {e.split(')')[0][1..-1] => e.split(')')[1] }
        end
      else
        content = sf.content.gsub("(DE-588a)(VIAF)", "(VIAF)")
        content.split("; ").each do |e|
          refs << {e.split(')')[0][1..-1] => e.split(')')[1] }
        end
      end
    end
    refs.each do |h|
      h.each do |k,v|
        tag_024 = Nokogiri::XML::Node.new "datafield", node
        tag_024['tag'] = '024'
        tag_024['ind1'] = '7'
        tag_024['ind2'] = ' '
        sfa = Nokogiri::XML::Node.new "subfield", node
        sfa['code'] = 'a'
        sfa.content = v
        sf2 = Nokogiri::XML::Node.new "subfield", node
        sf2['code'] = '2'
        sf2.content = k.gsub("DE-588a", "DNB")
        tag_024 << sfa << sf2
        subfields.first.parent.add_previous_sibling(tag_024)
      end
    end
    node.xpath("//marc:datafield[@tag='035']", NAMESPACE).first.remove unless subfields.empty?
  end

  def zr_addition_change_243
    tags=node.xpath("//marc:datafield[@tag='243']", NAMESPACE)
    tags.each do |sf|
      sfa = Nokogiri::XML::Node.new "subfield", node
      sfa['code'] = 'g'
      sfa.content = "RAK"
      sf << sfa
      tags.attr("tag", "730")
    end
  end

  def zr_addition_transfer_url
    subfields=node.xpath("//marc:datafield[@tag='856']/marc:subfield[@code='u']", NAMESPACE)
    subfields.each do |sf|
      sf2 = Nokogiri::XML::Node.new "subfield", node
      sf2['code'] = 'z'
      sf2.content = 'DIGITALISAT'
      sf.parent << sf2
    end
    subfields=node.xpath("//marc:datafield[@tag='500']/marc:subfield[@code='a']", NAMESPACE)
    subfields.each do |sf|
      if sf.content.ends_with_url?
        #puts sf.content
        urlbem = sf.content.split(": ")[0]
        url = sf.content.split(": ")[1]
        tag_856 = Nokogiri::XML::Node.new "datafield", node
        tag_856['tag'] = '856'
        tag_856['ind1'] = '0'
        tag_856['ind2'] = ' '
        sfa = Nokogiri::XML::Node.new "subfield", node
        sfa['code'] = 'u'
        sfa.content = url
        sf2 = Nokogiri::XML::Node.new "subfield", node
        sf2['code'] = 'z'
        sf2.content = urlbem
        tag_856 << sfa << sf2
        node.root << tag_856
        sf.parent.remove
      end
    end
  end

  def zr_addition_prefix_performance
    subfield=node.xpath("//marc:datafield[@tag='518']/marc:subfield[@code='a']", NAMESPACE)
    subfield.each { |sf| sf.content = "Performance date: #{sf.content}" }
  end

  def zr_addition_add_isil
    controlfield=node.xpath("//marc:controlfield[@tag='003']", NAMESPACE)
    controlfield.each { |sf| sf.content = "DE-633" }
  end

  def zr_addition_change_cataloging_source 
    subfield=node.xpath("//marc:datafield[@tag='040']/marc:subfield[@code='a']", NAMESPACE)
    subfield.each { |sf| sf.content = "DE-633" }
  end


  def zr_addition_split_730
    datafields = node.xpath("//marc:datafield[@tag='730']", NAMESPACE)
    return 0 if datafields.empty?
    datafields.each do |datafield|
      hs = datafield.xpath("marc:subfield[@code='a']", NAMESPACE)
      title = split_hs(hs.map(&:text).join(""))
      hs.each { |sf| sf.content = title[:hs] }
      sfk = Nokogiri::XML::Node.new "subfield", node
      sfk['code'] = 'g'
      sfk.content = "RISM"
      datafield << sfk
      if title[:sub]
        sfk = Nokogiri::XML::Node.new "subfield", node
        sfk['code'] = 'k'
        sfk.content = title[:sub]
        datafield << sfk
      end
      if title[:arr]
        sfk = Nokogiri::XML::Node.new "subfield", node
        sfk['code'] = 'o'
        sfk.content = title[:arr]
        datafield << sfk
      end
    end
  end

  def zr_addition_person_add_profession
    datafields = node.xpath("//marc:datafield[@tag='559']", NAMESPACE)
    return 0 if datafields.empty?
    datafields.each do |datafield|
      sfk = Nokogiri::XML::Node.new "subfield", node
      sfk['code'] = 'i'
      sfk.content = "profession"
      datafield << sfk
    end
  end

  def zr_addition_person_split_510(connection)
    scoring = node.xpath("//marc:datafield[@tag='510']/marc:subfield[@code='a']", NAMESPACE)
    return 0 if scoring.empty?
    scoring.each do |tag|
      entries = tag.content.split("; ")
      entries.each do |entry|
        curs = connection.exec("select k0001 from ksprpd where bvsigl='#{entry}'")
        if db = curs.fetch_hash
          k0001 = db['K0001']
          curs.close
          tag = Nokogiri::XML::Node.new "datafield", node
          tag['tag'] = '510'
          tag['ind1'] = ' '
          tag['ind2'] = ' '
          sfa = Nokogiri::XML::Node.new "subfield", node
          sfa['code'] = 'a'
          sfa.content = entry.strip
          tag << sfa
          sf0 = Nokogiri::XML::Node.new "subfield", node
          sf0['code'] = '0'
          sf0.content = k0001
          tag << sf0
          node.root << tag
        else
          next
        end
      end
    end
    rnode = node.xpath("//marc:datafield[@tag='510']", NAMESPACE).first
    rnode.remove if rnode
  end

  def zr_addition_person_add_670_id(connection)
    lit_ids = {
      "Brown-StrattonBMB" => 1480, 
      "DEUMM/b suppl." => 2957,
      "DEUMM/b" => 1577,          
      "ČSHS" => 1625,
      "EitnerQ" => 1272,
      "FétisB|2" => 1574,
      "FétisB|2 suppl." => 995,
      "Frank-AltmannTL|1|5 suppl." => 2497,
      "Frank-AltmannTL|1|5" => 2497,
      "Grove|6" => 1258,
      "Grove|7" => 3072,                                  
      "Kutsch-RiemensGSL|4" => 30026016,
      "MCL" => 1635,
      "MGG" => 1263,
      "MGG suppl." => 2495,
      "MGG|2/p" => 3828,                                                          
      "MGG|2/s" => 1290,
      "MGG|2 suppl." => 30020107,                                              
      "RISM A/I" => 3806,
      "RISM A/I suppl." => 3808,
      "RISM B/I" => 30000057,
      "SCHML" => 3013,
      "Sohlmans|2" => 1282,
      "StiegerO" => 1231,
      "RiemannL|1|2/p" => 408,
      "RiemannL|1|2/p suppl." => 2496,
      "RiemannL|1|3" => 30026906,
      "VollhardtC 1899" => 1624
    }

    scoring = node.xpath("//marc:datafield[@tag='670']/marc:subfield[@code='a']", NAMESPACE)
    return 0 if scoring.empty?
    scoring.each do |tag|
      entry = tag.content.split(": ")[0]
      fd = tag.content.split(": ")[1]
      if lit_ids.include?(entry)
        a0001=lit_ids[entry]
      else
        #puts entry
        return 0 if !entry || entry.empty?
        curs = connection.exec("select a0001 from akprpd where a0376=:1", entry.force_encoding("ISO-8859-1"))
        if db = curs.fetch_hash
          a0001 = db['A0001']
          curs.close
        else
          next
        end
      end
      sf0 = Nokogiri::XML::Node.new "subfield", node
      sf0['code'] = 'w'
      sf0.content = a0001
      tag.add_next_sibling(sf0)
      sfb = Nokogiri::XML::Node.new "subfield", node
      sfb['code'] = 'b'
      sfb.content = fd
      tag.add_next_sibling(sfb)
      tag.content = entry
    end
  end



  def remove_unlinked_authorities
    tags = %w(100$0 504$0 510$0 700$0 710$0 852$x)
    tags.each do |tag|
      df, sf = tag.split("$")
      nodes = node.xpath("//marc:datafield[@tag='#{df}']", NAMESPACE)
      nodes.each do |n|
        subfield = n.xpath("marc:subfield[@code='#{sf}']", NAMESPACE)
        if !subfield || subfield.empty? || (subfield.first.content.empty? || !(subfield.first.content =~ /^[0-9]+$/))
          rism_id = node.xpath("//marc:controlfield[@tag='001']", NAMESPACE).first.content
          logger.debug("EMPTY AUTHORITY NODE in #{rism_id}: #{n.to_s}")
          if df == '510' and n.xpath("marc:subfield[@code='a']", NAMESPACE).first.content == 'RISM B/I'
            sf0 = Nokogiri::XML::Node.new "subfield", node
            sf0['code'] = '0'
            sf0.content = "30000057"
            n << sf0
          else
            n.remove
          end
        end
      end
    end
  end


  #DEPRECATED
  def zr_addition_remove_empty_linked_fields
    taglist = %w(100 690 691 700 710)
    taglist.each do |tag|
      datafields = node.xpath("//marc:datafield[@tag='#{tag}']/marc:subfield[@code='0']", NAMESPACE)
      datafields.each do |df|
        puts df
        if df.content.empty?
          binding.pry
          df.parent.remove
        end
      end
    end
  end

  def zr_addition_move_852c
    fields = node.xpath("//marc:datafield[@tag='852']", NAMESPACE)
    fields.each do |field|
      subfields = field.xpath("marc:subfield[@code='p']", NAMESPACE)
      if subfields.size > 1
        rism_id = node.xpath("//marc:controlfield[@tag='001']", NAMESPACE).first.content
        logger.debug("DUBLICATE SHELFMARK NODE in #{rism_id}: #{field.to_s}")
        subfields[1..-1].each do |subfield|
          tag = Nokogiri::XML::Node.new "datafield", node
          tag['tag'] = '591'
          tag['ind1'] = ' '
          tag['ind2'] = ' '
          sfa = Nokogiri::XML::Node.new "subfield", node
          sfa['code'] = 'a'
          sfa.content = subfield.content
          tag << sfa
          node.root << tag
          subfield.remove
        end
      end
    end
  end



  def convert_attribution(str)
    case str
    when "e"
      return "Ascertained"
    when "z"
      return "Doubtful"
    when "g"
      return "Verified"
    when "f"
      return "Misattributed"
    when "l"
      return "Alleged"
    when "m"
      return "Conjectural"
    else
      return str
    end
  end

  def convert_593_abbreviation(str)
    case str
    when "mw"
      return "other type"
    when "mt"
      return "theoreticum, handwritten"
    when "ml"
      return "libretto, handwritten"
    when "mu"
      return "theoreticum, printed"
    when "mv"
      return "unknown"
    else
      return str
    end
  end

  def convert_gender(str)
    case str
    when "m"
      return "male"
    when "w"
      return "female"
    else
      return "unknown"
    end
  end

  def convert_individualize(str)
    case str
    when "a"
      return "individualized"
    when "b"
      return "not individualized"
    else
      return "unknown"
    end
  end

  def convert_media(str)
    case str
    when "0"
      return "Printed book"
    when "ae"
      return "Sheet music"
    when "1"
      return "Manuscript"
    when "er"
      return "Electronic resource"
    when "aj"
      return "CD-ROM"
    when "ak"
      return "Combination"
    else
      return "Other"
    end
  end

  

  def split_hs(str)
    str.gsub!(/\?$/, "")
    title={}
    title[:hs] = str unless str.include?(".")
    fields = str.split(".")
    if fields.size == 2
      title[:hs] = fields[0]
      title[:sub] = fields[1].strip if fields[1].strip.size > 3
      title[:arr] = fields[1].strip if fields[1].strip.size <= 3
    elsif fields.size == 3
      title[:hs] = fields[0]
      title[:sub] = fields[1].strip
      title[:arr] = fields[2].strip
    else
      title[:hs] = str
    end
    return title




  end

end


