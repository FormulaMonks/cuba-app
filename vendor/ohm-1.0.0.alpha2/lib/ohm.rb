# encoding: UTF-8

require "nest"
require "redis"
require "securerandom"
require "scrivener"
require "ohm/transaction"

module Ohm

  # All of the known errors in Ohm can be traced back to one of these
  # exceptions.
  #
  # MissingID:
  #
  #   Comment.new.id # => Error
  #   Comment.new.key # => Error
  #
  #   Solution: you need to save your model first.
  #
  # IndexNotFound:
  #
  #   Comment.find(foo: "Bar") # => Error
  #
  #   Solution: add an index with `Comment.index :foo`.
  #
  # UniqueIndexViolation:
  #
  #   Raised when trying to save an object with a `unique` index for
  #   which the value already exists.
  #
  #   Solution: rescue `Ohm::UniqueIndexViolation` during save, but
  #   also, do some validations even before attempting to save.
  #
  class Error < StandardError; end
  class MissingID < Error; end
  class IndexNotFound < Error; end
  class UniqueIndexViolation < Error; end

  # Instead of monkey patching Kernel or trying to be clever, it's
  # best to confine all the helper methods in a Utils module.
  module Utils

    # Used by: `attribute`, `counter`, `set`, `reference`,
    # `collection`.
    #
    # Employed as a solution to avoid `NameError` problems when trying
    # to load models referring to other models not yet loaded.
    #
    # Example:
    #
    #   class Comment < Ohm::Model
    #     reference :user, User # NameError undefined constant User.
    #   end
    #
    #   Instead of relying on some clever `const_missing` hack, we can
    #   simply use a Symbol.
    #
    #   class Comment < Ohm::Model
    #     reference :user, :User
    #   end
    #
    def self.const(context, name)
      case name
      when Symbol then context.const_get(name)
      else name
      end
    end
  end

  class Connection
    attr_accessor :context
    attr_accessor :options

    def initialize(context = :main, options = {})
      @context = context
      @options = options
    end

    def reset!
      threaded[context] = nil
    end

    def start(options = {})
      self.options = options
      self.reset!
    end

    def redis
      threaded[context] ||= Redis.connect(options)
    end

    def threaded
      Thread.current[:ohm] ||= {}
    end
  end

  def self.conn
    @conn ||= Connection.new
  end

  # Stores the connection options for the Redis instance.
  #
  # Examples:
  #
  #   Ohm.connect(port: 6380, db: 1, host: "10.0.1.1")
  #   Ohm.connect(url: "redis://10.0.1.1:6380/1")
  #
  # All of the options are simply passed on to `Redis.connect`.
  #
  def self.connect(options = {})
    conn.start(options)
  end

  # Use this if you want to do quick ad hoc redis commands against the
  # defined Ohm connection.
  #
  # Examples:
  #
  #   Ohm.redis.keys("User:*")
  #   Ohm.redis.set("foo", "bar")
  #
  def self.redis
    conn.redis
  end

  # Wrapper for Ohm.redis.flushdb.
  def self.flush
    redis.flushdb
  end

  # Defines most of the methods used by `Set` and `MultiSet`.
  module Collection
    include Enumerable

    # Fetch the data from Redis in one go.
    def to_a
      fetch(ids)
    end

    def each
      to_a.each { |e| yield e }
    end

    def empty?
      size == 0
    end

    # Allows you to sort by any field in your model.
    #
    # Example:
    #
    #   class User < Ohm::Model
    #     attribute :name
    #   end
    #
    #   User.all.sort_by(:name, order: "ALPHA")
    #   User.all.sort_by(:name, order: "ALPHA DESC")
    #   User.all.sort_by(:name, order: "ALPHA DESC", limit: [0, 10])
    #
    # Note: This is slower compared to just doing `sort`, specifically
    # because Redis has to read each individual hash in order to sort
    # them.
    #
    def sort_by(att, options = {})
      sort(options.merge(by: namespace["*->%s" % att]))
    end

    # Allows you to sort your models using their IDs. This is much
    # faster than `sort_by`. If you simply want to get records in
    # ascending or descending order, then this is the best method to
    # do that.
    #
    # Example:
    #
    #   class User < Ohm::Model
    #     attribute :name
    #   end
    #
    #   User.create(name: "John")
    #   User.create(name: "Jane")
    #
    #   User.all.sort.map(&:id) == ["1", "2"]
    #   # => true
    #
    #   User.all.sort(order: "ASC").map(&:id) == ["1", "2"]
    #   # => true
    #
    #   User.all.sort(order: "DESC").map(&:id) == ["2", "1"]
    #   # => true
    #
    def sort(options = {})
      if options.has_key?(:get)
        options[:get] = namespace["*->%s" % options[:get]]
        return execute { |key| key.sort(options) }
      end

      fetch(execute { |key| key.sort(options) })
    end

    # Check if a model is included in this set.
    #
    # Example:
    #
    #   u = User.create
    #
    #   User.all.include?(u)
    #   # => true
    #
    # Note: Ohm simply checks that the model's ID is included in the
    # set. It doesn't do any form of type checking.
    #
    def include?(model)
      exists?(model.id)
    end

    # Returns the total size of the set using SCARD.
    def size
      execute { |key| key.scard }
    end

    # Syntactic sugar for `sort_by` or `sort` when you only need the
    # first element.
    #
    # Example:
    #
    #   User.all.first ==
    #     User.all.sort(limit: [0, 1]).first
    #
    #   User.all.first(by: :name, "ALPHA") ==
    #     User.all.sort_by(:name, order: "ALPHA", limit: [0, 1]).first
    #
    def first(options = {})
      opts = options.dup
      opts.merge!(limit: [0, 1])

      if opts[:by]
        sort_by(opts.delete(:by), opts).first
      else
        sort(opts).first
      end
    end

    # Grab all the elements of this set using SMEMBERS.
    def ids
      execute { |key| key.smembers }
    end

    # Retrieve a specific element using an ID from this set.
    #
    # Example:
    #
    #   # Let's say we got the ID 1 from a request parameter.
    #   id = 1
    #
    #   # Retrieve the post if it's included in the user's posts.
    #   post = user.posts[id]
    #
    def [](id)
      model[id] if exists?(id)
    end

  private
    def exists?(id)
      execute { |key| key.sismember(id) }
    end

    def fetch(ids)
      arr = model.db.pipelined do
        ids.each { |id| namespace[id].hgetall }
      end

      return [] if arr.nil?

      arr.map.with_index do |atts, idx|
        model.new(atts.update(id: ids[idx]))
      end
    end
  end

  class Set < Struct.new(:key, :namespace, :model)
    include Collection

    # Add a model directly to the set.
    #
    # Example:
    #
    #   user = User.create
    #   post = Post.create
    #
    #   user.posts.add(post)
    #
    def add(model)
      key.sadd(model.id)
    end

    # Remove a model directly from the set.
    #
    # Example:
    #
    #   user = User.create
    #   post = Post.create
    #
    #   user.posts.delete(post)
    #
    def delete(model)
      key.srem(model.id)
    end

    # Chain new fiters on an existing set.
    #
    # Example:
    #
    #   set = User.find(name: "John")
    #   set.find(age: 30)
    #
    def find(dict)
      keys = model.filters(dict)
      keys.push(key)

      MultiSet.new(keys, namespace, model)
    end

    # Reduce the set using any number of filters.
    #
    # Example:
    #
    #   set = User.find(name: "John")
    #   set.except(country: "US")
    #
    #   # You can also do it in one line.
    #   User.find(name: "John").except(country: "US")
    #
    def except(dict)
      MultiSet.new([key], namespace, model).except(dict)
    end

    # Do a union to the existing set using any number of filters.
    #
    # Example:
    #
    #   set = User.find(name: "John")
    #   set.union(name: "Jane")
    #
    #   # You can also do it in one line.
    #   User.find(name: "John").union(name: "Jane")
    #
    def union(dict)
      MultiSet.new([key], namespace, model).union(dict)
    end

    # Replace all the existing elements of a set with a different
    # collection of models. This happens atomically in a MULTI-EXEC
    # block.
    #
    # Example:
    #
    #   user = User.create
    #   p1 = Post.create
    #   user.posts.add(p1)
    #
    #   p2, p3 = Post.create, Post.create
    #   user.posts.replace([p2, p3])
    #
    #   user.posts.include?(p1)
    #   # => false
    #
    def replace(models)
      ids = models.map { |model| model.id }

      key.redis.multi do
        key.del
        ids.each { |id| key.sadd(id) }
      end
    end

  private
    def execute
      yield key
    end
  end

  # Anytime you filter a set with more than one requirement, you
  # internally use a `MultiSet`. `MutiSet` is a bit slower than just
  # a `Set` because it has to `SINTERSTORE` all the keys prior to
  # retrieving the members, size, etc.
  #
  # Example:
  #
  #   User.all.kind_of?(Ohm::Set)
  #   # => true
  #
  #   User.find(name: "John").kind_of?(Ohm::Set)
  #   # => true
  #
  #   User.find(name: "John", age: 30).kind_of?(Ohm::MultiSet)
  #   # => true
  #
  class MultiSet < Struct.new(:keys, :namespace, :model)
    include Collection

    # Chain new fiters on an existing set.
    #
    # Example:
    #
    #   set = User.find(name: "John", age: 30)
    #   set.find(status: 'pending')
    #
    def find(dict)
      keys = model.filters(dict)
      keys.push(*self.keys)

      MultiSet.new(keys, namespace, model)
    end

    # Reduce the set using any number of filters.
    #
    # Example:
    #
    #   set = User.find(name: "John")
    #   set.except(country: "US")
    #
    #   # You can also do it in one line.
    #   User.find(name: "John").except(country: "US")
    #
    def except(dict)
      sdiff.push(*model.filters(dict)).uniq!

      return self
    end

    # Do a union to the existing set using any number of filters.
    #
    # Example:
    #
    #   set = User.find(name: "John")
    #   set.union(name: "Jane")
    #
    #   # You can also do it in one line.
    #   User.find(name: "John").union(name: "Jane")
    #
    def union(dict)
      sunion.push(*model.filters(dict)).uniq!

      return self
    end

  private
    def sunion
      @sunion ||= []
    end

    def sdiff
      @sdiff ||= []
    end

    def execute
      key = namespace[:temp][SecureRandom.uuid]
      key.sinterstore(*keys)
      key.sdiffstore(key, *sdiff)   if sdiff.any?
      key.sunionstore(key, *sunion) if sunion.any?

      begin
        yield key
      ensure
        key.del
      end
    end
  end

  # The base class for all your models. In order to better understand
  # it, here is a semi-realtime explanation of the details involved
  # when creating a User instance.
  #
  # Example:
  #
  #   class User < Ohm::Model
  #     attribute :name
  #     index :name
  #
  #     attribute :email
  #     unique :email
  #
  #     counter :points
  #
  #     set :posts, :Post
  #   end
  #
  #   u = User.create(name: "John", email: "foo@bar.com")
  #   u.incr :points
  #   u.posts.add(Post.create)
  #
  # When you execute `User.create(...)`, you run the following Redis
  # commands:
  #
  #   # Generate an ID
  #   INCR User:id
  #
  #   # Add the newly generated ID, (let's assume the ID is 1).
  #   SADD User:all 1
  #
  #   # Store the unique index
  #   HSET User:uniques:email foo@bar.com 1
  #
  #   # Store the name index
  #   SADD User:indices:name:John 1
  #
  #   # Store the HASH
  #   HMSET User:1 name John email foo@bar.com
  #
  # Next we increment points:
  #
  #   HINCR User:1:counters points 1
  #
  # And then we add a Post to the `posts` set.
  # (For brevity, let's assume the Post created has an ID of 1).
  #
  #   SADD User:1:posts 1
  #
  class Model
    include Scrivener::Validations

    def self.conn
      @conn ||= Connection.new(name, Ohm.conn.options)
    end

    def self.connect(options)
      @key = nil
      @lua = nil
      conn.start(options)
    end

    def self.db
      conn.redis
    end

    def self.lua
      @lua ||= Lua.new(File.join(Dir.pwd, "lua"), db)
    end

    # The namespace for all the keys generated using this model.
    #
    # Example:
    #
    #   class User < Ohm::Model
    #
    #   User.key == "User"
    #   User.key.kind_of?(String)
    #   # => true
    #
    #   User.key.kind_of?(Nest)
    #   # => true
    #
    # To find out more about Nest, see:
    #   http://github.com/soveran/nest
    #
    def self.key
      @key ||= Nest.new(self.name, db)
    end

    # Retrieve a record by ID.
    #
    # Example:
    #
    #   u = User.create
    #   u == User[u.id]
    #   # =>  true
    #
    def self.[](id)
      new(id: id).load! if id && exists?(id)
    end

    # Retrieve a set of models given an array of IDs.
    #
    # Example:
    #
    #   ids = [1, 2, 3]
    #   ids.map(&User)
    #
    # Note: The use of this should be a last resort for your actual
    # application runtime, or for simply debugging in your console. If
    # you care about performance, you should pipeline your reads. For
    # more information checkout the implementation of Ohm::Set#fetch.
    #
    def self.to_proc
      lambda { |id| self[id] }
    end

    # Check if the ID exists within <Model>:all.
    def self.exists?(id)
      key[:all].sismember(id)
    end

    # Find values in `unique` indices.
    #
    # Example:
    #
    #   class User < Ohm::Model
    #     unique :email
    #   end
    #
    #   u = User.create(email: "foo@bar.com")
    #   u == User.with(:email, "foo@bar.com")
    #   # => true
    #
    def self.with(att, val)
      id = key[:uniques][att].hget(val)
      id && self[id]
    end

    # Find values in indexed fields.
    #
    # Example:
    #
    #   class User < Ohm::Model
    #     attribute :email
    #
    #     attribute :name
    #     index :name
    #
    #     attribute :status
    #     index :status
    #
    #     index :provider
    #     index :tag
    #
    #     def provider
    #       email[/@(.*?).com/, 1]
    #     end
    #
    #     def tag
    #       ["ruby", "python"]
    #     end
    #   end
    #
    #   u = User.create(name: "John", status: "pending", email: "foo@me.com")
    #   User.find(provider: "me", name: "John", status: "pending").include?(u)
    #   # => true
    #
    #   User.find(tag: "ruby").include?(u)
    #   # => true
    #
    #   User.find(tag: "python").include?(u)
    #   # => true
    #
    #   User.find(tag: ["ruby", "python"]).include?(u)
    #   # => true
    #
    def self.find(dict)
      keys = filters(dict)

      if keys.size == 1
        Ohm::Set.new(keys.first, key, self)
      else
        Ohm::MultiSet.new(keys, key, self)
      end
    end

    # Index any method on your model. Once you index a method, you can
    # use it in `find` statements.
    def self.index(attribute)
      indices << attribute unless indices.include?(attribute)
    end

    # Create a unique index for any method on your model. Once you add
    # a unique index, you can use it in `with` statements.
    #
    # Note: if there is a conflict while saving, an
    # `Ohm::UniqueIndexViolation` violation is raised.
    #
    def self.unique(attribute)
      uniques << attribute unless uniques.include?(attribute)
    end

    # Declare an Ohm::Set with the given name.
    #
    # Example:
    #
    #   class User < Ohm::Model
    #     set :posts, :Post
    #   end
    #
    #   u = User.create
    #   u.posts.empty?
    #   # => true
    #
    # Note: You can't use the set until you save the model. If you try
    # to do it, you'll receive an Ohm::MissingID error.
    #
    def self.set(name, model)
      collections << name unless collections.include?(name)

      define_method name do
        model = Utils.const(self.class, model)

        Ohm::Set.new(key[name], model.key, model)
      end
    end

    # A macro for defining a method which basically does a find.
    #
    # Example:
    #   class Post < Ohm::Model
    #     reference :user, :User
    #   end
    #
    #   class User < Ohm::Model
    #     collection :posts, :Post
    #   end
    #
    #   # is the same as
    #
    #   class User < Ohm::Model
    #     def posts
    #       Post.find(user_id: self.id)
    #     end
    #   end
    #
    def self.collection(name, model, reference = to_reference)
      define_method name do
        model = Utils.const(self.class, model)
        model.find(:"#{reference}_id" => id)
      end
    end

    # A macro for defining an attribute, an index, and an accessor
    # for a given model.
    #
    # Example:
    #
    #   class Post < Ohm::Model
    #     reference :user, :User
    #   end
    #
    #   # It's the same as:
    #
    #   class Post < Ohm::Model
    #     attribute :user_id
    #     index :user_id
    #
    #     def user
    #       @_memo[:user] ||= User[user_id]
    #     end
    #
    #     def user=(user)
    #       self.user_id = user.id
    #       @_memo[:user] = user
    #     end
    #
    #     def user_id=(user_id)
    #       @_memo.delete(:user_id)
    #       self.user_id = user_id
    #     end
    #   end
    #
    def self.reference(name, model)
      reader = :"#{name}_id"
      writer = :"#{name}_id="

      index reader

      define_method(reader) do
        @attributes[reader]
      end

      define_method(writer) do |value|
        @_memo.delete(name)
        @attributes[reader] = value
      end

      define_method(:"#{name}=") do |value|
        @_memo.delete(name)
        send(writer, value ? value.id : nil)
      end

      define_method(name) do
        @_memo[name] ||= begin
          model = Utils.const(self.class, model)
          model[send(reader)]
        end
      end
    end

    # The bread and butter macro of all models. Basically declares
    # persisted attributes. All attributes are stored on the Redis
    # hash.
    #
    # Example:
    #   class User < Ohm::Model
    #     attribute :name
    #   end
    #
    #   # It's the same as:
    #
    #   class User < Ohm::Model
    #     def name
    #       @attributes[:name]
    #     end
    #
    #     def name=(name)
    #       @attributes[:name] = name
    #     end
    #   end
    #
    def self.attribute(name, cast = nil)
      if cast
        define_method(name) do
          cast[@attributes[name]]
        end
      else
        define_method(name) do
          @attributes[name]
        end
      end

      define_method(:"#{name}=") do |value|
        @attributes[name] = value
      end
    end

    # Declare a counter. All the counters are internally stored in
    # a different Redis hash, independent from the one that stores
    # the model attributes. Counters are updated with the `incr` and
    # `decr` methods, which interact directly with Redis. Their value
    # can't be assigned as with regular attributes.
    #
    # Example:
    #
    #   class User < Ohm::Model
    #     counter :points
    #   end
    #
    #   u = User.create
    #   u.incr :points
    #
    #   Ohm.redis.hget "User:1:counters", "points"
    #   # => 1
    #
    # Note: You can't use counters until you save the model. If you
    # try to do it, you'll receive an Ohm::MissingID error.
    #
    def self.counter(name)
      define_method(name) do
        return 0 if new?

        key[:counters].hget(name).to_i
      end
    end

    # An Ohm::Set wrapper for Model.key[:all].
    def self.all
      Set.new(key[:all], key, self)
    end

    # Syntactic sugar for Model.new(atts).save
    def self.create(atts = {})
      new(atts).save
    end

    # Manipulate the Redis hash of attributes directly.
    #
    # Example:
    #
    #   class User < Ohm::Model
    #     attribute :name
    #   end
    #
    #   u = User.create(name: "John")
    #   u.key.hget(:name)
    #   # => John
    #
    # For more details see
    #   http://github.com/soveran/nest
    #
    def key
      model.key[id]
    end

    # Initialize a model using a dictionary of attributes.
    #
    # Example:
    #
    #   u = User.new(name: "John")
    #
    def initialize(atts = {})
      @attributes = {}
      @_memo = {}
      update_attributes(atts)
    end

    # Access the ID used to store this model. The ID is used together
    # with the name of the class in order to form the Redis key.
    #
    # Example:
    #
    #   class User < Ohm::Model; end
    #
    #   u = User.create
    #   u.id
    #   # => 1
    #
    #   u.key
    #   # => User:1
    #
    def id
      raise MissingID if not defined?(@id)
      @id
    end

    # Check for equality by doing the following assertions:
    #
    # 1. That the passed model is of the same type.
    # 2. That they represent the same Redis key.
    #
    def ==(other)
      other.kind_of?(model) && other.key == key
    rescue MissingID
      false
    end

    # Preload all the attributes of this model from Redis. Used
    # internally by `Model::[]`.
    def load!
      update_attributes(key.hgetall) unless new?
      return self
    end

    # Read an attribute remotly from Redis. Useful if you want to get
    # the most recent value of the attribute and not rely on locally
    # cached value.
    #
    # Example:
    #
    #   User.create(name: "A")
    #
    #   Session 1     |    Session 2
    #   --------------|------------------------
    #   u = User[1]   |    u = User[1]
    #   u.name = "B"  |
    #   u.save        |
    #                 |    u.name == "A"
    #                 |    u.get(:name) == "B"
    #
    def get(att)
      @attributes[att] = key.hget(att)
    end

    # Update an attribute value atomically. The best usecase for this
    # is when you simply want to update one value.
    #
    # Note: This method is dangerous because it doesn't update indices
    # and uniques. Use it wisely. The safe equivalent is `update`.
    #
    def set(att, val)
      val.to_s.empty? ? key.hdel(att) : key.hset(att, val)
      @attributes[att] = val
    end

    def new?
      !defined?(@id)
    end

    # Increment a counter atomically. Internally uses HINCRBY.
    def incr(att, count = 1)
      key[:counters].hincrby(att, count)
    end

    # Decrement a counter atomically. Internally uses HINCRBY.
    def decr(att, count = 1)
      incr(att, -count)
    end

    # Return a value that allows the use of models as hash keys.
    #
    # Example:
    #
    #   h = {}
    #
    #   u = User.new
    #
    #   h[:u] = u
    #   h[:u] == u
    #   # => true
    #
    def hash
      new? ? super : key.hash
    end
    alias :eql? :==

    def attributes
      @attributes
    end

    # Export the ID and the errors of the model. The approach of Ohm
    # is to whitelist public attributes, as opposed to exporting each
    # (possibly sensitive) attribute.
    #
    # Example:
    #
    #   class User < Ohm::Model
    #     attribute :name
    #   end
    #
    #   u = User.create(name: "John")
    #   u.to_hash
    #   # => { id: "1" }
    #
    # In order to add additional attributes, you can override `to_hash`:
    #
    #   class User < Ohm::Model
    #     attribute :name
    #
    #     def to_hash
    #       super.merge(name: name)
    #     end
    #   end
    #
    #   u = User.create(name: "John")
    #   u.to_hash
    #   # => { id: "1", name: "John" }
    #
    def to_hash
      attrs = {}
      attrs[:id] = id unless new?
      attrs[:errors] = errors if errors.any?

      return attrs
    end

    # Export a JSON representation of the model by encoding `to_hash`.
    def to_json(*args)
      to_hash.to_json(*args)
    end

    # Persist the model attributes and update indices and unique
    # indices. The `counter`s and `set`s are not touched during save.
    #
    # If the model is not valid, nil is returned. Otherwise, the
    # persisted model is returned.
    #
    # Example:
    #
    #   class User < Ohm::Model
    #     attribute :name
    #
    #     def validate
    #       assert_present :name
    #     end
    #   end
    #
    #   User.new(name: nil).save
    #   # => nil
    #
    #   u = User.new(name: "John").save
    #   u.kind_of?(User)
    #   # => true
    #
    def save(&block)
      return if not valid?
      save!(&block)
    end

    # Saves the model without checking for validity. Refer to
    # `Model#save` for more details.
    def save!
      transaction do |t|
        t.watch(*_unique_keys)
        t.watch(key) if not new?

        t.before do
          _initialize_id if new?
        end

        t.read do |store|
          _verify_uniques
          store.existing = key.hgetall
          store.uniques  = _read_index_type(:uniques)
          store.indices  = _read_index_type(:indices)
        end

        t.write do |store|
          model.key[:all].sadd(id)
          _delete_uniques(store.existing)
          _delete_indices(store.existing)
          _save
          _save_indices(store.indices)
          _save_uniques(store.uniques)
        end

        yield t if block_given?
      end

      return self
    end

    # Delete the model, including all the following keys:
    #
    # - <Model>:<id>
    # - <Model>:<id>:counters
    # - <Model>:<id>:<set name>
    #
    # If the model has uniques or indices, they're also cleaned up.
    #
    def delete
      transaction do |t|
        t.read do |store|
          store.existing = key.hgetall
        end

        t.write do |store|
          _delete_uniques(store.existing)
          _delete_indices(store.existing)
          model.collections.each { |e| key[e].del }
          model.key[:all].srem(id)
          key[:counters].del
          key.del
        end

        yield t if block_given?
      end
    end

    # Update the model attributes and call save.
    #
    # Example:
    #
    #   User[1].update(name: "John")
    #
    #   # It's the same as:
    #
    #   u = User[1]
    #   u.update_attributes(name: "John")
    #   u.save
    #
    def update(attributes)
      update_attributes(attributes)
      save
    end

    # Write the dictionary of key-value pairs to the model.
    def update_attributes(atts)
      atts.each { |att, val| send(:"#{att}=", val) }
    end

  protected
    def self.to_reference
      name.to_s.
        match(/^(?:.*::)*(.*)$/)[1].
        gsub(/([a-z\d])([A-Z])/, '\1_\2').
        downcase.to_sym
    end

    def self.indices
      @indices ||= []
    end

    def self.uniques
      @uniques ||= []
    end

    def self.collections
      @collections ||= []
    end

    def self.filters(dict)
      unless dict.kind_of?(Hash)
        raise ArgumentError,
          "You need to supply a hash with filters. " +
          "If you want to find by ID, use #{self}[id] instead."
      end

      dict.map { |k, v| toindices(k, v) }.flatten
    end

    def self.toindices(att, val)
      raise IndexNotFound unless indices.include?(att)

      if val.kind_of?(Enumerable)
        val.map { |v| key[:indices][att][v] }
      else
        [key[:indices][att][val]]
      end
    end

    def self.new_id
      key[:id].incr
    end

    attr_writer :id

    def transaction
      txn = Transaction.new { |t| yield t }
      txn.commit(db)
    end

    def model
      self.class
    end

    def db
      model.db
    end

    def _initialize_id
      @id = model.new_id.to_s
    end

    def _skip_empty(atts)
      {}.tap do |ret|
        atts.each do |att, val|
          ret[att] = send(att).to_s unless val.to_s.empty?
        end
      end
    end

    def _unique_keys
      model.uniques.map { |att| model.key[:uniques][att] }
    end

    def _save
      key.del
      key.hmset(*_skip_empty(attributes).flatten)
    end

    def _verify_uniques
      if att = _detect_duplicate
        raise UniqueIndexViolation, "#{att} is not unique."
      end
    end

    def _detect_duplicate
      model.uniques.detect do |att|
        id = model.key[:uniques][att].hget(send(att))
        id && id != self.id.to_s
      end
    end

    def _read_index_type(type)
      {}.tap do |ret|
        model.send(type).each do |att|
          ret[att] = send(att)
        end
      end
    end

    def _save_uniques(uniques)
      uniques.each do |att, val|
        model.key[:uniques][att].hset(val, id)
      end
    end

    def _delete_uniques(atts)
      model.uniques.each do |att|
        model.key[:uniques][att].hdel(atts[att.to_s])
      end
    end

    def _delete_indices(atts)
      model.indices.each do |att|
        val = atts[att.to_s]

        if val
          model.key[:indices][att][val].srem(id)
        end
      end
    end

    def _save_indices(indices)
      indices.each do |att, val|
        model.toindices(att, val).each do |index|
          index.sadd(id)
        end
      end
    end
  end

  class Lua
    attr :dir
    attr :redis
    attr :files
    attr :scripts

    def initialize(dir, redis)
      @dir = dir
      @redis = redis
      @files = Hash.new { |h, cmd| h[cmd] = read(cmd) }
      @scripts = {}
    end

    def run_file(file, options)
      run(files[file], options)
    end

    def run(script, options)
      keys = options[:keys]
      argv = options[:argv]

      begin
        redis.evalsha(sha(script), keys.size, *keys, *argv)
      rescue RuntimeError
        redis.eval(script, keys.size, *keys, *argv)
      end
    end

  private
    def read(file)
      File.read("%s/%s.lua" % [dir, file])
    end

    def sha(script)
      Digest::SHA1.hexdigest(script)
    end
  end
end
