require 'mongo/gridfs'
require 'mime/types'
require 'tempfile'
require 'mojo_magick'

# if thumbnailable?
#   tmp = Tempfile.new("thumb_#{filename}")
#   MojoMagick::resize(uploaded_file.path, tmp.path, {:width => 50, :height => 40, :scale => '>'})
#   self.thumbnail = tmp.read      
# end

# open    : db, name, mode, options (:root, :metadata, :content_type)
# read    : db, name, length, offset
# unlink  : db, names
# list    : db, root collection
#
# GridStore.open(database, 'filename', 'w') { |f|
#   f.puts "Hello, world!"
# }

module Grip
  def self.included(base)
    base.extend Grip::ClassMethods
    base.class_eval do
      after_save :save_attachments
      before_destroy :destroy_attached_files
    end
  end
  
  module ClassMethods
    def has_grid_attachment(name,opts={})
      write_inheritable_attribute(:attachment_definitions, {}) if attachment_definitions.nil?
      attachment_definitions[name] = opts
      
      key "#{name}_size".to_sym, Integer
      key "#{name}_path".to_sym, String
      key "#{name}_name".to_sym, String
      key "#{name}_content_type".to_sym, String
      
      define_method(name) do
        # open returns the correct mime-type, read returns a string. Not sure if 
        # this is a GridFS problem or not
        GridFS::GridStore.open(self.class.database, self["#{name}_path"], 'r') {|f| f }
      end
      
      define_method("#{name}=") do |file|
        raise Grip::InvalidFileException unless (file.is_a?(File) || file.is_a?(Tempfile))
        self['_id']                  = Mongo::ObjectID.new if _id.blank?
        self["#{name}_size"]         = File.size(file) 
        self["#{name}_name"]         = File.basename(file.path)
        self["#{name}_path"]         = "#{self.class.to_s.underscore}/#{name}/#{_id}"
        self["#{name}_content_type"] = file.content_type rescue MIME::Types.type_for(self["#{name}_name"]).to_s
        self.class.attachment_definitions[name][:file] = file
      end
      
      unless opts[:versions].nil?
        opts[:versions].each do |v,dimensions|
          key "#{name}_#{v}_size".to_sym, Integer
          key "#{name}_#{v}_path".to_sym, String
          key "#{name}_#{v}_name".to_sym, String
          key "#{name}_#{v}_content_type".to_sym, String
          
          define_method("#{name}_#{v}") do
            # open returns the correct mime-type, read returns a string. Not sure if 
            # this is a GridFS problem or not
            GridFS::GridStore.open(self.class.database, self["#{name}_#{v}_path"], 'r') {|f| f }
          end

          define_method("#{name}_#{v}=") do |file|
            raise Grip::InvalidFileException unless (file.is_a?(File) || file.is_a?(Tempfile))
            self['_id']                  = Mongo::ObjectID.new if _id.blank?
            self["#{name}_#{v}_size"]         = File.size(file) 
            self["#{name}_#{v}_name"]         = File.basename(file.path)
            self["#{name}_#{v}_path"]         = "#{self.class.to_s.underscore}/#{name}/#{v}/#{_id}"
            
            self["#{name}_#{v}_content_type"] = self["#{name}_content_type"]
          end
          
        end
      end
      
    end
    
    def attachment_definitions
      read_inheritable_attribute(:attachment_definitions)
    end
  end
  
  # Roll through attachment definitions and check if they are a File or Tempfile. Both types are 
  # nescessary for file uploads to work properly. Each file checks for a <attr_name>_process
  # callback for pre-processing before save.
  def save_attachments
    self.class.attachment_definitions.each do |definition|
      attr_name, opts = definition
      GridFS::GridStore.open(self.class.database, self["#{attr_name}_path"], 'w', :content_type => self["#{attr_name}_content_type"]) do |f|
        f.write send("process_#{attr_name}",opts) rescue opts[:file]
      end
      
      unless opts[:versions].nil?
        opts[:versions].each do |version,dimensions|
          tmp = Tempfile.new("#{attr_name}_#{version}")
          MojoMagick::resize(opts[:file].path, tmp.path, dimensions)
          send "#{attr_name}_#{version}=", tmp
          GridFS::GridStore.open(self.class.database, self["#{attr_name}_#{version}_path"], 'w', :content_type => self["#{attr_name}_content_type"]) do |f|
            f.write tmp.read
          end
        end
        save_to_collection
      end
      
    end
  end
  
  def destroy_attached_files
    self.class.attachment_definitions.each do |name, attachment|
      GridFS::GridStore.unlink(self.class.database, self["#{name}_path"])
      unless attachment[:versions].nil?
        attachment[:versions].each do |v,dim|
          GridFS::GridStore.unlink(self.class.database, self["#{name}_#{v}_path"])
        end
      end
    end
  end
  
  class Grip::InvalidFileException < Exception
  end
  
end
