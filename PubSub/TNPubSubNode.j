/*
 * TNPubSubNode.j
 *
 * Copyright (C) 2010  Antoine Mercadal <antoine.mercadal@inframonde.eu>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3.0 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

@import <Foundation/Foundation.j>

@import "../TNStropheGlobals.j"
@import "../TNStropheConnection.j"
@import "../TNStropheStanza.j"

// TODO: Abstract out subscription related stuff into TNPubSubNodeSubscription in order to handle multiple node subscriptions better

/*! @ingroup strophecappuccino
    this is an implementation of a XMPP Publish-Subscribe node
*/
@implementation TNPubSubNode : CPObject
{
    CPArray                 _content        @accessors(getter=content);
    CPString                _nodeName       @accessors(getter=name);
    id                      _delegate       @accessors(property=delegate);
    TNStopheJID             _pubSubServer   @accessors(getter=server);

    CPArray                 _subscriptionIDs;
    id                      _eventSelectorID;
    TNStropheConnection     _connection;
}


#pragma mark -
#pragma mark Class methods

/*! Register given selector of given object. When any pubsub event event is received, trigger the selector
    @param aSelector the selector
    @param anObject the object to use
    @param aConnection a valid connected TNStropheConnection
    @return int the id of the registration.
*/
+ (void)registerSelector:(SEL)aSelector ofObject:(id)anObject forPubSubEventWithConnection:(TNStropheConnection)aConnection
{
    var params = [CPDictionary dictionaryWithObjectsAndKeys:@"message", @"name",
                                                            @"headline", @"type",
                                                            {"matchBare": YES}, @"options",
                                                            Strophe.NS.PUBSUB_EVENT, @"namespace"];

    return [aConnection registerSelector:aSelector ofObject:anObject withDict:params];
}


#pragma mark -
#pragma mark Initialization

/*! create and initialize and return a new TNPubSubNode
    @param  aNodeName the name of the pubsub node
    @param  aConnection the TNStropheConnection to use to communicate
    @param aPubSubServer a pubsubserver. if nil, it will be pubsub. + domain of [_connection JID]
    @return initialized TNPubSubNode
*/
+ (TNPubSubNode)pubSubNodeWithNodeName:(CPString)aNodeName connection:(TNStropheConnection)aConnection pubSubServer:(CPString)aPubSubServer
{
    return [[TNPubSubNode alloc] initWithNodeName:aNodeName connection:aConnection pubSubServer:aPubSubServer];
}

/*! initialize and return a new TNPubSubNode
    @param  aNodeName the name of the pubsub node
    @param  aConnection the TNStropheConnection to use to communicate
    @param aPubSubServer a pubsubserver. if nil, it will be pubsub. + domain of [_connection JID]
    @return initialized TNPubSubNode
*/
- (TNPubSubNode)initWithNodeName:(CPString)aNodeName connection:(TNStropheConnection)aConnection pubSubServer:(TNStropheJID)aPubSubServer
{
    if (self = [super init])
    {
        _nodeName           = aNodeName;
        _connection         = aConnection;
        _pubSubServer       = aPubSubServer ? aPubSubServer : [TNStropheJID stropheJIDWithString:@"pubsub." + [[_connection JID] domain]];
        _subscriptionIDs    = [CPArray array];

        [self _setEventHandler];
    }

    return self;
}

/*! create and initialize and return a new TNPubSubNode
    @param  aNodeName the name of the pubsub node
    @param  aConnection the TNStropheConnection to use to communicate
    @param  aPubSubServer a pubsubserver. if nil, it will be pubsub. + domain of [_connection JID]
    @param  aSubscriptionIDs array of the subsciption IDs if already subscribed
    @return initialized TNPubSubNode
*/
+ (TNPubSubNode)pubSubNodeWithNodeName:(CPString)aNodeName connection:(TNStropheConnection)aConnection pubSubServer:(TNStropheJID)aPubSubServer subscriptionIDs:(CPArray)aSubscriptionIDs
{
    return [[TNPubSubNode alloc] initWithNodeName:aNodeName connection:aConnection pubSubServer:aPubSubServer subscriptionIDs:aSubscriptionIDs];
}

/*! initialize and return a new TNPubSubNode
    @param  aNodeName the name of the pubsub node
    @param  aConnection the TNStropheConnection to use to communicate
    @param  aPubSubServer a pubsubserver. if nil, it will be pubsub. + domain of [_connection JID]
    @param  aSubscriptionIDs array of the subsciption IDs if already subscribed
    @return initialized TNPubSubNode
*/
- (TNPubSubNode)initWithNodeName:(CPString)aNodeName connection:(TNStropheConnection)aConnection pubSubServer:(CPString)aPubSubServer subscriptionIDs:(CPArray)aSubscriptionIDs
{
    if (self = [self initWithNodeName:aNodeName connection:aConnection pubSubServer:aPubSubServer])
    {
        _subscriptionIDs = aSubscriptionIDs;
    }

    return self;
}


#pragma mark -
#pragma mark Node Management

/*! retrieve the content of the PubSub node from the server and call _didRetrievePubSubNode selector
    You should use this method to get past content
*/
- (void)retrieveItems
{
    var uid     = [_connection getUniqueId],
        stanza  = [TNStropheStanza iq],
        params  = [CPDictionary dictionaryWithObjectsAndKeys:uid, @"id"];

    [stanza setTo:_pubSubServer];
    [stanza setType:@"get"];
    [stanza setID:uid];

    [stanza addChildWithName:@"pubsub" andAttributes:{@"xmlns": Strophe.NS.PUBSUB}];
    [stanza addChildWithName:@"items" andAttributes:{@"node": _nodeName}];

    [_connection registerSelector:@selector(_didRetrievePubSubNode:) ofObject:self withDict:params];
    [_connection send:stanza];
}

/*! send TNStrophePubSubNodeRetrievedNotification if everything is ok
    @param aStanza TNStropheStanza contaning the response of the server
    @return NO in order to unregister the selector from connection
*/
- (BOOL)_didRetrievePubSubNode:(TNStropheStanza)aStanza
{
    if ([aStanza type] == @"result")
    {
        _content = [aStanza childrenWithName:@"item"];
        [[CPNotificationCenter defaultCenter] postNotificationName:TNStrophePubSubNodeRetrievedNotification object:self];
        if (_delegate && [_delegate respondsToSelector:@selector(pubSubNode:retrievedItems:)])
            [_delegate pubSubNode:self retrievedItems:YES];
    }
    else
    {
        if (_delegate && [_delegate respondsToSelector:@selector(pubSubNode:retrievedItems:)])
            [_delegate pubSubNode:self retrievedItems:NO];
        CPLog.error("Cannot retrieve the contents of pubsub node");
        CPLog.error(aStanza);
    }

    return NO;
}

/*! ask server to create the pubsub node and call _didCreatePubSubNode selector
*/
- (void)create
{
    var uid     = [_connection getUniqueId],
        stanza  = [TNStropheStanza iq],
        params  = [CPDictionary dictionaryWithObjectsAndKeys:uid, @"id"];

    [stanza setTo:_pubSubServer];
    [stanza setType:@"set"];
    [stanza setID:uid];

    [stanza addChildWithName:@"pubsub" andAttributes:{@"xmlns": Strophe.NS.PUBSUB}];
    [stanza addChildWithName:@"create" andAttributes:{@"node": _nodeName}];

    [_connection registerSelector:@selector(_didCreatePubSubNode:) ofObject:self withDict:params];
    [_connection send:stanza];
}

/*! send TNStrophePubSubNodeCreatedNotification if everything is OK
    @param aStanza TNStropheStanza contaning the response of the server
    @return NO in order to unregister the selector from connection
*/
- (BOOL)_didCreatePubSubNode:(TNStropheStanza)aStanza
{
    if ([aStanza type] == @"result")
        [[CPNotificationCenter defaultCenter] postNotificationName:TNStrophePubSubNodeCreatedNotification object:self];
    else
    {
        CPLog.error("Cannot create the pubsub node");
        CPLog.error(aStanza);
    }


    return NO;
}

/*! ask the server to delete the pubsub node
*/
- (void)delete
{
    var uid     = [_connection getUniqueId],
        stanza  = [TNStropheStanza iq],
        params  = [CPDictionary dictionaryWithObjectsAndKeys:uid, @"id"];

    [stanza setTo:_pubSubServer];
    [stanza setType:@"set"];
    [stanza setID:uid];

    [stanza addChildWithName:@"pubsub" andAttributes:{@"xmlns": Strophe.NS.PUBSUB_OWNER}];
    [stanza addChildWithName:@"delete" andAttributes:{@"node": _nodeName}];

    [_connection registerSelector:@selector(didDeletePubSubNode:) ofObject:self withDict:params];
    [_connection send:stanza];
}

/*! send TNStrophePubSubNodeDeleted if everything is OK
    @param aStanza TNStropheStanza contaning the response of the server
    @return NO in order to unregister the selector from connection
*/
- (BOOL)_didCreatePubSubNode:(TNStropheStanza)aStanza
{
    if ([aStanza type] == @"result")
        [[CPNotificationCenter defaultCenter] postNotificationName:TNStrophePubSubNodeDeletedNotification object:self];
    else
    {
        CPLog.error("Cannot delete the pubsub node");
        CPLog.error(aStanza);
    }


    return NO;
}

/*! configure the pubsub node with given directory. This dictionary can be for example

    [CPDictionary dictionaryWithObjectsAndKeys:1, TNStrophePubSubVarDeliverNotification,
                                               10, TNStrophePubSubVarMaxItems,
                                               0, TNStrophePubSubVarPurgeOffline];
    See XEP-0060 for more information about configuring a PubSubNode.

    @param aDictionary CPDictionary containing the configuration of the node
*/
- (void)configureWithDict:(CPDictionary)aDictionary
{
    var uid     = [_connection getUniqueId],
        stanza  = [TNStropheStanza iq],
        params  = [CPDictionary dictionaryWithObjectsAndKeys:uid, @"id"];

    [stanza setTo:_pubSubServer];
    [stanza setType:@"set"];
    [stanza setID:uid];

    [stanza addChildWithName:@"pubsub" andAttributes:{@"xmlns": Strophe.NS.PUBSUB_OWNER}];
    [stanza addChildWithName:@"configure" andAttributes:{@"node": _nodeName}];
    [stanza addChildWithName:@"x" andAttributes:{@"xmlns": "jabber:x:data", @"type": @"submit"}];
    [stanza addChildWithName:@"field" andAttributes:{@"var": @"FORM_TYPE", @"type": @"hidden"}];
    [stanza addChildWithName:@"value"];
    [stanza addTextNode:Strophe.NS.PUBSUB_NODE_CONFIG];
    [stanza up];
    [stanza up];

    for (var i = 0; i < [[aDictionary allKeys] count]; i++)
    {
        var key     = [[aDictionary allKeys] objectAtIndex:i],
            value   = [aDictionary objectForKey:key];

        [stanza addChildWithName:@"field" andAttributes:{@"var": key}];

        if ([value class] == CPArray)
        {
            for (var j = 0; j < [value count]; j++)
            {
                [stanza addChildWithName:@"value"];
                [stanza addTextNode:@"" + [value objectAtIndex:j] + @""];
                [stanza up];
            }
        }
        else
        {
            [stanza addChildWithName:@"value"];
            [stanza addTextNode:@"" + value + @""];
            [stanza up];
        }
        [stanza up];
    }

    [_connection registerSelector:@selector(_didConfigurePubSubNode:) ofObject:self withDict:params];
    [_connection send:stanza];
}

/*! send TNStrophePubSubNodeConfiguredNotification if everything is OK
    @param aStanza TNStropheStanza contaning the response of the server
    @return NO in order to unregister the selector from connection
*/
- (BOOL)_didConfigurePubSubNode:(TNStropheStanza)aStanza
{
    if ([aStanza type] == @"result")
        [[CPNotificationCenter defaultCenter] postNotificationName:TNStrophePubSubNodeConfiguredNotification object:self];
    else
    {
        CPLog.error("Cannot configure the pubsub node");
        CPLog.error(aStanza);
    }

    return NO;
}


#pragma mark -
#pragma mark Item management

/*! Ask the server to publish a new item containing the content of the given TNXMLNode
    @params anItem TNXMLNode containing the content of the item
*/
- (void)publishItem:(TNXMLNode)anItem
{
    var uid     = [_connection getUniqueId],
        stanza  = [TNStropheStanza iq],
        params  = [CPDictionary dictionaryWithObjectsAndKeys:uid, @"id"];

    [stanza setTo:_pubSubServer];
    [stanza setType:@"set"];
    [stanza setID:uid];

    [stanza addChildWithName:@"pubsub" andAttributes:{@"xmlns": Strophe.NS.PUBSUB}];
    [stanza addChildWithName:@"publish" andAttributes:{@"node": _nodeName}];
    [stanza addChildWithName:@"item"];
    [stanza addNode:anItem];

    [_connection registerSelector:@selector(_didPublishPubSubItem:) ofObject:self withDict:params];
    [_connection send:stanza];
}

/*! will recover the content of node if everything is OK
    @param aStanza TNStropheStanza contaning the response of the server
    @return NO in order to unregister the selector from connection
*/
- (BOOL)_didPublishPubSubItem:(TNStropheStanza)aStanza
{
    if ([aStanza type] == @"result")
    {
        [[CPNotificationCenter defaultCenter] addObserver:self selector:@selector(_didUpdateContentAfterPublishing:) name:TNStrophePubSubNodeRetrievedNotification object:self];
        [self retrieveItems];
    }
    else
    {
        CPLog.error("Cannot publish the pubsub item in node");
        CPLog.error(aStanza);
    }


    return NO;
}

/*! send TNStrophePubSubItemPublishedNotification if everything is OK
    @param aNotification CPNotification given by [TNPubSubNode recover]
*/
- (void)_didUpdateContentAfterPublishing:(CPNotification)aNotification
{
    [[CPNotificationCenter defaultCenter] removeObserver:self name:TNStrophePubSubNodeRetrievedNotification object:self];
    [[CPNotificationCenter defaultCenter] postNotificationName:TNStrophePubSubItemPublishedNotification object:self];
}


/*! Ask the server to retract (remove) a node
    @params aNode the node to remove
*/
- (void)retractItem:(TNXMLNode)aNode
{
    [self retractItemWithID:[aNode valueForAttribute:@"id"]];
}

/*! Ask the server to retract (remove) a new item according to the given ID
    @params anID CPString containing the ID of the item to retract
*/
- (void)retractItemWithID:(CPString)anID
{
    var uid     = [_connection getUniqueId],
        stanza  = [TNStropheStanza iq],
        params  = [CPDictionary dictionaryWithObjectsAndKeys:uid, @"id"];

    [stanza setTo:_pubSubServer];
    [stanza setType:@"set"];
    [stanza setID:uid];

    [stanza addChildWithName:@"pubsub" andAttributes:{@"xmlns": Strophe.NS.PUBSUB}];
    [stanza addChildWithName:@"retract" andAttributes:{@"node": _nodeName}];
    [stanza addChildWithName:@"item" andAttributes:{@"id": anID}];

    [_connection registerSelector:@selector(_didRetractPubSubItem:) ofObject:self withDict:params];
    [_connection send:stanza];
}

/*! will recover the content of node if everything is OK
    @param aStanza TNStropheStanza contaning the response of the server
    @return NO in order to unregister the selector from connection
*/
- (BOOL)_didRetractPubSubItem:(TNStropheStanza)aStanza
{
    if ([aStanza type] == @"result")
    {
        [[CPNotificationCenter defaultCenter] addObserver:self selector:@selector(_didUpdateContentAfterRetracting:) name:TNStrophePubSubNodeRetrievedNotification object:self];
        [self retrieveItems];
    }
    else
    {
        CPLog.error("Cannot remove the pubsub item in node");
        CPLog.error(aStanza);
    }

    return NO;
}

/*! send TNStrophePubSubItemRetractedNotification if everything is OK
    @param aNotification CPNotification given by [TNPubSubNode recover]
*/
- (void)_didUpdateContentAfterRetracting:(CPNotification)aNotification
{
    [[CPNotificationCenter defaultCenter] removeObserver:self name:TNStrophePubSubNodeRetrievedNotification object:self];
    [[CPNotificationCenter defaultCenter] postNotificationName:TNStrophePubSubItemRetractedNotification object:self];
}


#pragma mark -
#pragma mark Subscription Management

/*! Ask the server to subscribe to the node in order to recieve events
*/
- (void)subscribe
{
    [self subscribeWithOptions:nil];
}

/*! Ask the server to subscribe to the node in order to recieve events
    @param options key value pairs of subscription options
*/
- (void)subscribeWithOptions:(CPDictionary)options
{
    var uid    = [_connection getUniqueId],
        stanza = [TNStropheStanza iq],
        params = [CPDictionary dictionaryWithObjectsAndKeys:uid, @"id"];

    [stanza setType:@"set"];
    [stanza setID:uid];
    [stanza setTo:_pubSubServer];

    [stanza addChildWithName:@"pubsub" andAttributes:{@"xmlns": Strophe.NS.PUBSUB}];
    [stanza addChildWithName:@"subscribe" andAttributes:{@"node": _nodeName, @"jid": [[_connection JID] bare]}];

    if (options && [options count] > 0)
    {
        [subscribeStanza up];
        [subscribeStanza addChildWithName:@"options"];
        [subscribeStanza addChildWithName:@"x" andAttributes:{"xmlns":Strophe.NS.X_DATA, "type":"submit"}];
        [subscribeStanza addChildWithName:@"field" andAttributes:{"var":"FORM_TYPE", "type":"hidden"}];
        [subscribeStanza addChildWithName:@"value"];
        [subscribeStanza addTextNode:Strophe.NS.PUBSUB_SUBSCRIBE_OPTIONS];
        [subscribeStanza up];
        [subscribeStanza up];

        var keys = [options allKeys];
        for (var i = 0; i < [keys count]; i++)
        {
            var key     = [keys objectAtIndex:i],
                value   = [options valueForKey:key];
            [subscribeStanza addChildWithName:@"field" andAttributes:{"var":key}];
            [subscribeStanza addChildWithName:@"value"];
            [subscribeStanza addTextNode:value];
            [subscribeStanza up];
            [subscribeStanza up];
        }
    }

    [_connection registerSelector:@selector(_didSubscribe:) ofObject:self withDict:params]
    [_connection send:stanza];
}

/*! send TNStrophePubSubNodeSubscribedNotification if everything is OK and register __didReceiveEvent:
    that will eventually call the delegate selector pubsubNode:receivedEvent: when an event is recieved
    @param aStanza TNStropheStanza contaning the response of the server
    @return NO in order to unregister the selector from connection
*/
- (BOOL)_didSubscribe:(TNStropheStanza)aStanza
{
    if ([aStanza type] == @"result")
    {
        var subscription    = [aStanza firstChildWithName:@"subscription"],
            subID           = [subscription valueForAttribute:@"subid"],
            status          = [subscription valueForAttribute:@"subscription"];

        if ([subID length] > 0)
            [_subscriptionIDs addObject:subID];

        if (status === @"subscribed")
        {
            [[CPNotificationCenter defaultCenter] postNotificationName:TNStrophePubSubNodeSubscribedNotification object:self];
            if (_delegate && [_delegate respondsToSelector:@selector(pubSubNode:subscribed:)])
                [_delegate pubSubNode:self subscribed:YES];
        }


        [self _setEventHandler];
    }
    else
    {
        if (_delegate && [_delegate respondsToSelector:@selector(pubSubNode:subscribed:)])
            [_delegate pubSubNode:self subscribed:NO];
        CPLog.error("Cannot subscribe the pubsub node");
        CPLog.error(aStanza);

    }

    return NO;
}

- (void)addSubscriptionID:(CPString)aSubscriptionID
{
    [_subscriptionIDs addObject:aSubscriptionID];
}

/*! Ask the server to unsubscribe from the node in order to no longer recieve events
    @param aSubID string representing the specific subscription ID to unsubscribe
*/
- (void)unsubscribeWithSubID:(CPString)aSubID
{
    var uid    = [_connection getUniqueId],
        stanza = [TNStropheStanza iq],
        params = [CPDictionary dictionaryWithObjectsAndKeys:uid, @"id"];

    [stanza setType:@"set"];
    [stanza setID:uid];
    [stanza setTo:_pubSubServer];

    [stanza addChildWithName:@"pubsub" andAttributes:{"xmlns": Strophe.NS.PUBSUB}];
    [stanza addChildWithName:@"unsubscribe" andAttributes:{"node": _nodeName, "jid": [[_connection JID] bare]}];
    if (aSubID)
        [stanza setValue:aSubID forAttribute:@"subid"];

    [_connection registerSelector:@selector(_didUnsubscribe:) ofObject:self withDict:params];
    [_connection send:stanza];
}

/*! Remove all known subscriptions
*/
- (void)unsubscribe
{
    if ([_subscriptionIDs count] > 0)
    {
        // Unsubscribe from node for each subscription ID
        for (var i = 0; i < [_subscriptionIDs count]; i++)
        {
            [self unsubscribeWithSubID:[_subscriptionIDs objectAtIndex:i]];
        }
    }
    else
    {
        // There are no registered subscription IDs - send plain unsubscribe
        [self unsubscribeWithSubID:nil];
    }
}

/*! send TNStrophePubSubNodeUnsubscribedNotification if everything is OK and unregister __didReceiveEvent:
    @param aStanza TNStropheStanza contaning the response of the server
    @return NO in order to unregister the selector from connection
*/
- (BOOL)_didUnsubscribe:(TNStropheStanza)aStanza
{
    if ([aStanza type] == @"result")
    {
        var params  = [CPDictionary dictionary],
            subID   = [[[aStanza firstChildWithName:@"pubsub"] firstChildWithName:@"subscription"] valueForAttribute:@"subid"];

        if ([subID length] > 0)
        {
            [_subscriptionIDs removeObject:subID];
            [params setObject:subID forKey:@"subscriptionID"];
        }
        else if ([_subscriptionIDs count] === 1)
        {
            // TODO: Need to establish if subscription id is ever included in unsubscribe confirmation or if this association needs to be made by IQ id
            [_subscriptionIDs removeAllObjects];
        }

        if ([_subscriptionIDs count] === 0)
        {
            // No subscriptions remaining
            if (_eventSelectorID)
            {
                [_connection deleteRegisteredSelector:_eventSelectorID];
                _eventSelectorID = nil;
            }
        }

        [[CPNotificationCenter defaultCenter] postNotificationName:TNStrophePubSubNodeUnsubscribedNotification object:self userInfo:params];
        if (_delegate && [_delegate respondsToSelector:@selector(pubSubNode:unsubscribed:)])
            [_delegate pubSubNode:self unsubscribed:YES];

    }
    else
    {
        if (_delegate && [_delegate respondsToSelector:@selector(pubSubNode:unsubscribed:)])
            [_delegate pubSubNode:self unsubscribed:NO];
        CPLog.error("Cannot unsubscribe the pubsub node");
        CPLog.error(aStanza);
    }


    return NO;
}

- (int)numberOfSubscriptions
{
    return [_subscriptionIDs count];
}


#pragma mark -
#pragma mark Event Management

- (void)_setEventHandler
{
    var params = [CPDictionary dictionaryWithObjectsAndKeys:@"message", @"name",
                                                            [_pubSubServer node], @"from"];
    _eventSelectorID = [_connection registerSelector:@selector(_didReceiveEvent:) ofObject:self withDict:params];
}

/*! this message is send when a new pubsub event is recieved. It will call the delegate
    pubsubNode:receivedEvent: if any selector and send TNStrophePubSubNodeEventNotification notification
    @param aStanza TNStropheStanza contaning the response of the server
    @return YES in order to keep the selector registered
*/
- (BOOL)_didReceiveEvent:(TNStropheStanza)aStanza
{
    var pubsubEvent = [aStanza firstChildWithName:@"event"];

    if ([pubsubEvent namespace] != Strophe.NS.PUBSUB_EVENT)
        return YES;

    if ([pubsubEvent containsChildrenWithName:@"subscription"])
    {
        var subscription    = [pubsubEvent firstChildWithName:@"subscription"],
            status          = [subscription valueForAttribute:@"subscription"],
            nodeName        = [subscription valueForAttribute:@"node"];

        if (status === @"subscribed" && nodeName === _nodeName)
            [[CPNotificationCenter defaultCenter] postNotificationName:TNStrophePubSubNodeSubscribedNotification object:self];

        return YES;
    }

    if (_nodeName != [[pubsubEvent firstChildWithName:@"items"] valueForAttribute:@"node"])
        return YES;

    if (_delegate && [_delegate respondsToSelector:@selector(pubSubNode:receivedEvent:)])
        [_delegate pubSubNode:self receivedEvent:aStanza];

    [[CPNotificationCenter defaultCenter] postNotificationName:TNStrophePubSubNodeEventNotification object:self userInfo:aStanza];

    return YES;
}


- (CPString)description
{
    return _nodeName;
}

@end
