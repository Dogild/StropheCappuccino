/*  
 * TNStropheRoster.j
 *    
 * Copyright (C) 2010 Antoine Mercadal <antoine.mercadal@inframonde.eu>
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 * 
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

@import <Foundation/Foundation.j>

@import "TNStropheConnection.j";
@import "TNStropheStanza.j";
@import "TNStropheGroup.j"
@import "TNStropheContact.j"



//TNStropheRosterAskRetrievingNotification            = @"TNStropheRosterAskRetrievingNotification";
TNStropheRosterRetrievedNotification                = @"TNStropheRosterRetrievedNotification";
TNStropheRosterAddedContactNotification             = @"TNStropheRosterAddedContactNotification";
TNStropheRosterRemovedContactNotification           = @"TNStropheRosterRemovedContactNotification";
TNStropheRosterAddedGroupNotification               = @"TNStropheRosterAddedGroupNotification";



/*! @ingroup strophecappuccino
    this is an implementation of a basic XMPP Roster
*/
@implementation TNStropheRoster : CPObject 
{
    CPMutableArray          contacts        @accessors;
    CPMutableArray          groups          @accessors;
    id                      delegate        @accessors;
    
    TNStropheConnection     _connection;
}

// instance methods
- (id)initWithConnection:(TNStropheConnection)aConnection 
{
    if (self = [super init])
    {
        _connection= aConnection;
        [self setContacts:[[CPMutableArray alloc] init]];
        [self setGroups:[[CPMutableArray alloc] init]];

        var params = [[CPDictionary alloc] init];
        [params setValue:@"presence" forKey:@"name"];
        [params setValue:@"subscribe" forKey:@"type"];
        [params setValue:[_connection jid] forKey:@"to"];
        [_connection registerSelector:@selector(presenceSubscriptionRequestHandler:) ofObject:self withDict:params];
    }

    return self;
}

- (BOOL)presenceSubscriptionRequestHandler:(id)requestStanza 
{
    if ([[self delegate] respondsToSelector:@selector(didReceiveSubscriptionRequest:)])
        [[self delegate] performSelector:@selector(didReceiveSubscriptionRequest:) withObject:requestStanza];

    return YES;
}

- (CPArray)getRoster
{
    var uid         = [_connection getUniqueId:@"roster"];    
    var params      = [[CPDictionary alloc] init];
    var rosteriq    = [TNStropheStanza iqWithAttributes:{'id':uid, 'type':'get'}];
    
    [rosteriq addChildName:@"query" withAttributes:{'xmlns':Strophe.NS.ROSTER}];
    
    [params setValue:@"iq" forKey:@"name"];
    [params setValue:@"result" forKey:@"type"];
    [params setValue:uid forKey:@"id"];
    [_connection registerSelector:@selector(_didRosterReceived:) ofObject:self withDict:params];
    
    [_connection send:rosteriq];
}

- (BOOL)_didRosterReceived:(id)aStanza 
{
    var query   = [aStanza firstChildWithName:@"query"];
    var items   = [query childrenWithName:@"item"];
    
    for (var i = 0; i < [items count]; i++)
    {
        var item = [items objectAtIndex:i];
        
        if ([item valueForAttribute:@"name"])
            var nickname = [item valueForAttribute:@"name"];
        
        var theJid = [item valueForAttribute:@"jid"];
        
        if (![self doesRosterContainsJID:theJid])
        {
            var theGroup = ([item firstChildWithName:@"group"] != null) ? [[item firstChildWithName:@"group"] text] : "General";
            [self addGroupIfNotExists:theGroup];

        	var contact = [TNStropheContact contactWithConnection:_connection jid:theJid group:theGroup];
            [contact setNickname:nickname];

            [contact getStatus];
            [contact getMessages];
           	[[self contacts] addObject:contact];
        }
    	
    }
    
    //announce complete roster retrieved
    var center = [CPNotificationCenter defaultCenter];
    [center postNotificationName:TNStropheRosterRetrievedNotification object:self];
    
    return YES;
}


// Contact management
- (TNStropheContact) getContactFromJID:(CPString)aJid
{
    //@each (var contact in [self contacts])
    for(var i = 0; i < [[self contacts] count]; i++)
    {
        var contact = [[self contacts] objectAtIndex:i];
        if ([contact jid] == aJid)
            return contact;
    }
    
    return nil; 
}

- (BOOL)doesRosterContainsJID:(CPString)aJid
{
    //@each (var contact in [self contacts])
    for(var i = 0; i < [[self contacts] count]; i++)
    {
        var contact = [[self contacts] objectAtIndex:i];
        
        if ([[contact jid] lowercaseString] == [aJid lowercaseString])
            return YES;
    }
    return NO;
}

- (void)addContact:(CPString)aJid withName:(CPString)aName inGroup:(CPString)aGroup
{
    if ([self doesRosterContainsJID:aJid] == YES)
        return;

    if (!aGroup)
           aGroup = "General";
    
    var uid     = [_connection getUniqueId];
    //var params  = [CPDictionary dictionaryWithObjectsAndKeys:uid, @"id"];
    var addReq  = [TNStropheStanza iqWithAttributes:{"type": "set", "id": uid}];
    
    [addReq addChildName:@"query" withAttributes: {'xmlns':Strophe.NS.ROSTER}];
    [addReq addChildName:@"item" withAttributes:{"jid": aJid, "name": aName}];
    [addReq addChildName:@"group" withAttributes:nil];
    [addReq addTextNode:aGroup];
    
    //[_connection registerSelector:@selector(didAddContact:) ofObject:self withDict:params]
    [_connection send:addReq];
    
    var contact = [TNStropheContact contactWithConnection:_connection jid:aJid group:aGroup];
    [contact setNickname:aName];
    [contact getStatus];
    [contact getMessages];
    
    [[self addGroupIfNotExists:aGroup]]
   	[[self contacts] addObject:contact];
   	
   	var center = [CPNotificationCenter defaultCenter];
    [center postNotificationName:TNStropheRosterAddedContactNotification object:contact];
}


- (void)removeContact:(CPString)aJid 
{
    var contact = [self getContactFromJID:aJid];
    if (contact) 
    {
        [[self contacts] removeObject:contact];
        
        var uid         = [_connection getUniqueId];
        var removeReq   = [TNStropheStanza iqWithAttributes:{"type": "set", "id": uid}];
        
        [removeReq addChildName:@"query" withAttributes: {'xmlns':Strophe.NS.ROSTER}];
        [removeReq addChildName:@"item" withAttributes:{'jid': aJid, 'subscription': 'remove'}];
        
        [_connection send:removeReq];
        
        var center = [CPNotificationCenter defaultCenter];
        [center postNotificationName:TNStropheRosterRemovedContactNotification object:contact];
    }
}

- (void)changeNickname:(CPString)aName forJID:(CPString)aJid
{
    var contact = [self getContactFromJID:aJid];
    [contact changeNickname:aName];
}

- (void) changeGroup:(CPString)aGroup forJID:(CPString)aJid
{
    var contact = [self getContactFromJID:aJid];
    [contact changeGroup:aGroup];
}


// group management
- (TNStropheGroup)getGroupFromName:(CPString)aGroupName
{
    //@each (var group in [self groups])
    for(var i = 0; i < [[self groups] count]; i++)
    {
        var group = [[self groups] objectAtIndex:i];
        
        if ([group name] == aGroupName)
        return group;
    }
    return nil;
}

- (BOOL)doesRosterContainsGroup:(CPString)aGroup
{
    //@each (var group in [self groups])
    for(var i = 0; i < [[self groups] count]; i++)
    {
        var group = [[self groups] objectAtIndex:i];
        
        if ([group name] == aGroup)
            return YES;
    }   
    return NO;
}

- (TNStropheGroup)addGroup:(CPString)groupName
{
    var newGroup = [[TNStropheGroup alloc] init];

    [newGroup setName:groupName];
    [[self groups] addObject:newGroup];
    
    var center = [CPNotificationCenter defaultCenter];
    [center postNotificationName:TNStropheRosterAddedGroupNotification object:newGroup];
    
    return newGroup;
}

- (TNStropheGroup) addGroupIfNotExists:(CPString)groupName
{
    if (![self doesRosterContainsGroup:groupName])
        return [self addGroup:groupName];
    return nil;
}

- (BOOL)removeGroup:(CPString)aGroupName
{
    // TODO
}

- (CPArray)getContactsInGroup:(TNStropheGroup)aGroup
{
    var ret = [[CPArray alloc] init];

    //@each (var contact in [self contacts])
    for(var i = 0; i < [[self contacts] count]; i++)
    {
        var contact = [[self contacts] objectAtIndex:i];
        
        if ([contact group] == aGroup)
            [ret addObject:contact];
    }
    return ret;
}


// Authorizations management
- (void)authorizeJID:(CPString)aJid 
{
    var resp = [TNStropheStanza presenceWithAttributes:{"from": [_connection jid], "type": "subscribed", "to": aJid}];
    [_connection send:resp];
}

- (void)unauthorizeJID:(CPString)aJid
{
    var resp = [TNStropheStanza presenceWithAttributes:{"from": [_connection jid], "type": "unsubscribed", "to": aJid}];
    [_connection send:resp];
}

- (void)askAuthorizationTo:(CPString)aJid
{
    var uid     = [_connection getUniqueId];
    var params  = [CPDictionary dictionaryWithObjectsAndKeys:uid, @"id"];
    var auth    = [TNStropheStanza presenceWithAttributes:{"type": "subscribe", "to": aJid}];
    
    console.log([auth stringValue]);
    
    [_connection send:auth];
}

- (void)answerAuthorizationRequest:(id)aStanza answer:(BOOL)theAnswer
{
    var requester   = [aStanza getFrom];
    
    if (theAnswer == YES)
    {
        [self authorizeJID:requester];
        [self askAuthorizationTo:requester];
    }
    else
        [self unauthorizeJID:requester];
    
    if (![self doesRosterContainsJID:requester])
        [self addContact:requester withName:requester inGroup:nil]; 
        
}


// disconnection
- (void) disconnect
{
    [_connection disconnect];
}
@end
