
#PROMISES LIBRARY
bb = require 'bluebird'
_ = require "underscore"
#bb.Promise.longStackTraces();

# HAPI STACK
Hapi = require 'hapi'
Joi = require 'joi'

# GER
g = require 'ger'
knex = g.knex # postgres client


GER = g.GER

#ESMs
PsqlESM = g.PsqlESM
MemESM = g.MemESM

ret_esm = require 'ger_rethinkdb_esm'
RethinkDBESM = ret_esm.esm
r = ret_esm.r



Utils = {}

Utils.handle_error = (logger, err, reply) ->
  if err.isBoom
    logger.log(['error'], err)
    reply(err)
  else
    console.log "Unhandled Error", err, err.stack
    logger.log(['error'], {error: "#{err}", stack: err.stack})
    reply({error: "An unexpected error occurred"}).code(500)


class HapiGER
  constructor: (options = {}) ->
    @options = _.defaults(options, {
      esm: 'memory'
      esmoptions: {}
      port: 3456
      logging_options: {
        # reporters: [{
        #   reporter: require('good-console'),
        #   args: [{ log: '*', response: '*' }]
        # }]
      }
    })

    switch @options.esm
      when 'memory'
        @_esm = new MemESM(@options.namespace, {})
        @_ger = new GER(@_esm, @options)
      when 'pg'
        throw new Error('No esm_url') if !@options.esmoptions.connection
        esm_options = _.defaults(@options.esmoptions, {
          client: 'pg'
        })
        knex = new knex(esm_options)
        @_esm = new PsqlESM(@options.namespace, {knex: knex})
        @_ger = new GER(@_esm, @options)
      when 'rethinkdb'
        rethinkcon = new r(@options.esmoptions)
        @_esm = new RethinkDBESM(@options.namespace, {r: rethinkcon})
        @_ger = new GER(@_esm, @options)
      else
        throw new Error("no such esm")

  initialize: () ->
    bb.try( => @init_server())
    .then( => @setup_server())
    .then( => @add_server_routes())

  init_server: (esm = 'mem') ->
    #SETUP SERVER
    @_server = new Hapi.Server()
    @_server.connection({ port: @options.port });
    @info = @_server.info
    @_ger.initialize_namespace() #add the default namespace

  setup_server: ->
    @load_server_plugin('good', @options.logging_options)

  add_server_routes: ->
    @load_server_plugin('./the_hapi_ger', {ger : @_ger})

  server_method: (method, args = []) ->
    d = bb.defer()
    @_server.methods[method].apply(@, args.concat((err, result) ->
      if (err)
        d.reject(err)
      else
        d.resolve(result)
    ))
    d.promise


  start: ->
    console.log "Starting Server on #{@options.port}"
    @start_server()

  stop: ->
    @stop_server()

  load_server_plugin: (plugin, options = {}) ->
    d = bb.defer()
    @_server.register({register: require(plugin), options: options}, (err) ->
      if (err)
        d.reject(err)
      else
        d.resolve()
    )
    d.promise

  start_server: ->
    d = bb.defer()
    @_server.start( =>
      d.resolve(@)
    )
    d.promise

  stop_server: ->
    d = bb.defer()
    @_server.stop( ->
      d.resolve()
    )
    d.promise



module.exports = HapiGER