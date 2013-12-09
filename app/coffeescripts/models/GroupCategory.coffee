define [
  'underscore'
  'Backbone'
  'compiled/collections/GroupCollection'
  'compiled/collections/GroupUserCollection'
  'compiled/collections/UnassignedGroupUserCollection'
  'compiled/models/progressable'
  'compiled/backbone-ext/DefaultUrlMixin'
], (_, Backbone, GroupCollection, GroupUserCollection, UnassignedGroupUserCollection, progressable, DefaultUrlMixin) ->

  class GroupCategory extends Backbone.Model

    resourceName: "group_categories"
    @mixin progressable

    groups: ->
      @_groups = new GroupCollection null,
        category: this
        loadAll: true
      if @get('groups_count') is 0
        @_groups.loadedAll = true
      else
        @_groups.fetch()
      @_groups.on 'fetched:last', => @set('groups_count', @_groups.length)
      @_groups.on 'remove', @groupRemoved
      @groups = -> @_groups
      @_groups

    groupRemoved: (group) =>
      # update/reset the unassigned users collection (if it's around)
      return unless @_unassignedUsers or group.usersCount()

      users = group.users()
      if users.loadedAll
        models = users.models.slice()
        user.set 'groupId', null for user in models
      else
        @_unassignedUsers.increment group.usersCount()

      if not users.loadedAll or not @_unassignedUsers.loadedAll
        @_unassignedUsers.fetch()

    reassignUser: (user, newGroupId) ->
      oldGroupId = user.get('groupId')
      return if oldGroupId is newGroupId

      # if user is in _unassignedUsers and we allow multiple memberships,
      # don't actually move the user, move a copy instead
      if not oldGroupId? and @get('allows_multiple_memberships')
        user = user.clone()
        user.once 'change:groupId', => @groupUsersFor(newGroupId).addUser user

      user.save groupId: newGroupId

    groupsCount: ->
      if @_groups?.loadedAll
        @_groups.length
      else
        @get('groups_count')

    groupUsersFor: (id) ->
      if id?
        @_groups?.get(id)?._users
      else
        @_unassignedUsers

    unassignedUsers: ->
      @_unassignedUsers = new UnassignedGroupUserCollection null,
        category: this
      @_unassignedUsers.on 'fetched:last', => @set('unassigned_users_count', @_unassignedUsers.length)
      @unassignedUsers = -> @_unassignedUsers
      @_unassignedUsers

    unassignedUsersCount: ->
      @get('unassigned_users_count')

    canAssignUnassignedMembers: ->
      @groupsCount() > 0 and
        not @get('allows_multiple_memberships') and
        @get('self_signup') isnt 'restricted'

    assignUnassignedMembers: ->
      $.ajaxJSON "/api/v1/group_categories/#{@id}/assign_unassigned_members", 'POST', {}, @setUpProgress

    setUpProgress: (response) =>
      @set progress_url: response.url

    present: ->
      data = Backbone.Model::toJSON.call(this)
      data.progress = @progressModel.toJSON()
      data

    toJSON: ->
      data = _.omit(super, 'self_signup', 'split_group_count')
      data.create_group_count ?= @get('split_group_count') if @get('split_groups')
      data

    @mixin DefaultUrlMixin

    sync: (method, model, options = {}) ->
      options.url = @urlFor(method)
      if method is 'create' and model.get('split_groups') is '1'
        success = options.success ? ->
        options.success = (args) =>
          @progressStarting = true
          success(args)
          @assignUnassignedMembers()
      else if method is 'delete'
        if model.progressModel
          model.progressModel.onPoll = ->
      Backbone.sync method, model, options

    urlFor: (method) ->
      if method is 'create'
        @_defaultUrl()
      else
        "/api/v1/group_categories/#{@id}?includes[]=unassigned_users_count&includes[]=groups_count"
