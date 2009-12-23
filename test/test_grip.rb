require "test_helper"

class Foo
  include MongoMapper::Document
  include Grip
  
  has_grid_attachment :image
  has_grid_attachment :pdf
end

class GripTest < Test::Unit::TestCase
  def setup
    MongoMapper.connection.drop_database "test-attachments"
    MongoMapper.database = "test-attachments"
    
    dir    = File.dirname(__FILE__) + '/fixtures'
    @pdf   = File.open("#{dir}/sample.pdf",  'r')
    @image = File.open("#{dir}/cthulhu.png", 'r')
    
    @doc = Foo.create(:image => @image, :pdf => @pdf)
    @doc.reload
  end
  
  def teardown
    @pdf.close
    @image.close
  end
  
  test "assigns keys correctly" do
    assert_equal 27582, @doc.image_size
    assert_equal 8775,  @doc.pdf_size
    
    assert_equal 'cthulhu.png', @doc.image_name
    assert_equal 'sample.pdf',  @doc.pdf_name
    
    assert_equal "image/png",       @doc.image_content_type
    assert_equal "application/pdf", @doc.pdf_content_type
    
    assert_equal "foo/image/#{@doc.id}", @doc.image_path
    assert_equal "foo/pdf/#{@doc.id}",   @doc.pdf_path
    
    collection = MongoMapper.database['fs.files']
    
    assert_equal "image/png", collection.find_one(:filename => @doc.image_path)['contentType']
    assert_equal "application/pdf", collection.find_one(:filename => @doc.pdf_path)['contentType']
  end
  
  test "responds to dynamic keys" do
    [ :pdf_size, :pdf_path, :pdf_name, :pdf_content_type,
      :image_size, :image_path, :image_name, :image_content_type
    ].each do |method|
      assert @doc.respond_to?(method)
    end
  end
  
  test "saves attachments correctly" do
    assert_equal @image.read, @doc.image
    assert_equal @pdf.read,   @doc.pdf
    
    assert GridFS::GridStore.exist?(MongoMapper.database, @doc.image_path)
    assert GridFS::GridStore.exist?(MongoMapper.database, @doc.pdf_path)
  end
  
  test "cleans up attachments on destroy" do
    assert GridFS::GridStore.exist?(MongoMapper.database, @doc.image_path)
    assert GridFS::GridStore.exist?(MongoMapper.database, @doc.pdf_path)
    
    @doc.destroy
    
    assert ! GridFS::GridStore.exist?(MongoMapper.database, @doc.image_path)
    assert ! GridFS::GridStore.exist?(MongoMapper.database, @doc.pdf_path)
  end
end