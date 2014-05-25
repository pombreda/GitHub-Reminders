require 'mongo'

module Mongo_Connection

	include Mongo

	def self.clear_mongo_collections
		@collRemindersUsers.remove
	end

	def self.addIntoMongo(mongoPayload)
		@collRemindersUsers.insert(mongoPayload)
	end

	def self.find_and_modify_document(options)
		@collRemindersUsers.find_and_modify(options)
	end

	def self.mongo_Connect(url, port, dbName, collName)
		@client = MongoClient.new(url, port)
		@db = @client[dbName]
		@collRemindersUsers = @db[collName]
	end

	def self.aggregate(input)
		@collRemindersUsers.aggregate(input)
	end


end