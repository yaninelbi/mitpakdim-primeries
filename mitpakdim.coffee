root = window.mit ?= {}
################### UTILITIES #####################
sum = (arr) ->
    do_sum = (item, memo) ->
        memo += item
    _.reduce(arr, do_sum, 0)

############### JQUERY UI EXTENSIONS ##############

$.widget "mit.agendaSlider", $.extend({}, $.ui.slider.prototype, {
    _create : (->
            cached_old_slider_create = $.ui.slider::_create
            new_create_func = ->
                @element.append '<div class="ui-slider-mid-marker"></div>'
                cached_old_slider_create.apply @
            new_create_func
        )()
    setMemberMarker : (value) ->
        member_marker_classname = "ui-slider-member-marker"
        if not @element.find(".#{member_marker_classname}").length
            handle = @element.find(".ui-slider-handle")
            handle.before "<div class='#{member_marker_classname}'></div>"
        @element.find(".#{member_marker_classname}").css
            left : value + "%"
})

############### SYNC ##############

root.JSONPSync = (method, model, options) ->
    options.dataType = "jsonp"
    return Backbone.sync(method, model, options)
############### MODELS ##############

class root.MiscModel extends Backbone.Model
class root.Agenda extends Backbone.Model
    defaults:
        uservalue: 0

class root.Candidate extends Backbone.Model
class root.Member extends root.Candidate
    defaults:
        score: 'N/A'

    class MemberAgenda extends Backbone.Model
        urlRoot: "http://api.dev.oknesset.org/api/v2/member-agendas/"
        sync: root.JSONPSync

    fetchAgendas: (force) ->
        if @agendas_fetching.state() != "resolved" or force
            @memberAgendas = new MemberAgenda
                id: @get 'id'
            @memberAgendas.fetch
                success: =>
                    @agendas_fetching.resolve()
                error: =>
                    console.log "Error fetching member agendas", @, arguments
                    @agendas_fetching.reject()

        return @agendas_fetching

    getAgendas: ->
        if @agendas_fetching.state() != "resolved"
            console.log "Trying to use member agendas before fetched", @, @agendas_fetching
            throw "Agendas not fetched yet!"
        @memberAgendas.get('agendas')

    initialize: ->
        @agendas_fetching = $.Deferred()

class root.NewCandidate extends root.Candidate

############### COLLECTIONS ##############

class root.LocalVarCollection extends Backbone.Collection
    initialize: (models, options) ->
        if options?.localObject
            console.log "Using local objects for ", this
            @localObject = options.localObject
        if options?.url
            @url = options.url
    sync: (method, model, options) =>
        if @localObject == undefined
            return @syncFunc arguments...

        setTimeout =>
            options.success @localObject, null # xhr
        return

    syncFunc: Backbone.sync

    parse: (response) ->
        return response.objects

class root.JSONPCollection extends root.LocalVarCollection
    syncFunc: root.JSONPSync

class root.MemberList extends root.JSONPCollection
    model: root.Member
    localObject: window.mit.members
    url: "http://api.dev.oknesset.org/api/v2/member/"
    fetchAgendas: ->
        fetches = []
        @each (member) =>
            fetches.push member.fetchAgendas()
        console.log "Waiting for " + fetches.length + " member agendas"
        @agendas_fetching = $.when(fetches...)
        .done =>
            console.log "Got results!", this, arguments
        .fail =>
            console.log "Error getting results!", this, arguments

############### VIEWS ##############

class root.TemplateView extends Backbone.View
    template: ->
        _.template( @get_template() )(arguments...)
    render: =>
        @$el.html( @template(@model.toJSON()) )
        @

class root.MemberView extends root.TemplateView
    className: "member_instance"
    get_template: ->
        $("#member_template").html()

class root.ListViewItem extends root.TemplateView
    tagName: "div"
    get_template: ->
        "<a href='#'><%= name %></a>"

class root.ListView extends root.TemplateView
    initialize: ->
        super(arguments...)
        @options.itemView ?= root.ListViewItem
        @options.autofetch ?= true
        if @options.collection
            @setCollection(@options.collection)

    setCollection: (collection) ->
        @collection = collection
        @collection.bind "add", @addOne
        @collection.bind "reset", @addAll
        if @options.autofetch
            @collection.fetch()

    addOne: (modelInstance) =>
        view = new @options.itemView({ model:modelInstance })
        modelInstance.view = view
        @$el.append view.render().$el

    addAll: =>
        @initEmptyView()
        @collection.each(@addOne)

    initEmptyView: =>
        @$el.empty()

class root.DropdownItem extends Backbone.View
    tagName: "option"
    render: =>
        json = @model.toJSON()
        @$el.html( json.name )
        @$el.attr({ value: json.id })
        @

class root.DropdownContainer extends root.ListView
    tagName: "select"
    options:
        itemView: root.DropdownItem
    initEmptyView: =>
        @$el.html("<option>-----</option>")

class root.CandidatesMainView extends Backbone.View
    el: ".candidates_container"
    initialize: ->

class root.MembersView extends root.ListView
    el: ".members"
    options:
        itemView: root.MemberView
        autofetch: false

    initialize: ->
        super(arguments...)
        @memberList = new root.MemberList
        @memberList.fetch()
        @setCollection new root.MemberList undefined,
            comparator: (member) ->
                return -member.get 'score'

    changeParty: (party) ->
        @collection.reset @memberList.where(party_name: party)
        @collection.fetchAgendas()

    calculate: (weights) ->
        if not @collection.agendas_fetching
            throw "Agenda data not present yet"
        @collection.agendas_fetching.done =>
            @calculate_inner(weights)
            @collection.sort()

    calculate_inner: (weights) ->
        weight_sum = sum(weights)

        console.log "Weights: ", weights
        @collection.each (member) =>
            member.set 'score', _.reduce member.getAgendas(), (memo, agenda) ->
                memo += weights[agenda.id] * agenda.score / weight_sum
            , 0

class root.AppView extends Backbone.View
    el: '#app_root'
    initialize: =>
        @candidatesView = new root.CandidatesMainView
        @membersView = new root.MembersView
        @partyListView = new root.DropdownContainer
            collection: new root.JSONPCollection(null,
                model: root.MiscModel
                url: "http://api.dev.oknesset.org/api/v2/party/"
                localObject: window.mit.parties
            )
        @$(".parties").append(@partyListView.$el)
        @partyListView.$el.bind('change', @partyChange)

        @agendaListView = new root.ListView
            collection: new root.JSONPCollection(null,
                model: root.Agenda
                localObject: window.mit.agendas
                url: "http://api.dev.oknesset.org/api/v2/agenda/"
            )
            itemView: class extends root.ListViewItem
                className : "agenda_item"
                render : ->
                    super()
                    @.$('.slider').agendaSlider
                        min : -100
                        max : 100
                        value : @model.get "uservalue"
                        stop : @onStop
                    @
                onStop : (event, ui) =>
                    @model.set
                        uservalue : ui.value
                get_template: ->
                    $("#agenda_template").html()

        @agendaListView.showMarkersForMember = (member_model) ->
            member_agendas = {}
            for agenda in member_model.getAgendas()
                member_agendas[agenda.id] = agenda.score
            @collection.each (agenda, index) ->
                value = member_agendas[agenda.id] or 0
                value = 50 + value / 2
                @.$(".slider").eq(index).agendaSlider "setMemberMarker", value

        @agendaListView.collection.on 'change', =>
            console.log "Model changed", arguments
            if @recalc_timeout
                clearTimeout @recalc_timeout
            recalc_timeout = setTimeout =>
                @recalc_timeout = null
                @calculate()
            , 100
        @$(".agendas").append(@agendaListView.$el)
        @agendaListView.$el.bind('change', @agendaChange)

    partyChange: =>
        console.log "Changed: ", this, arguments
        @membersView.changeParty @partyListView.$('option:selected').text()

    memberClicked : (click_ev) =>
        instance_el = $(click_ev.target).closest('.member_instance')
        instance_index = @memberListView.$el.find(".member_instance").index(instance_el)
        member_model = @filteredMemberList.at(instance_index)
        @agendaListView.showMarkersForMember member_model

    calculate: ->
        weights = {}
        @agendaListView.collection.each (agenda) =>
            uservalue = agenda.get("uservalue")
            weights[agenda.get('id')] = uservalue
        @membersView.calculate(weights)


############### INIT ##############

$ ->
    root.appView = new root.AppView
    return
