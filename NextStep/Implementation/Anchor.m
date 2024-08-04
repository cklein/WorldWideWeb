/*	Hypertext "Anchor" Object				Anchor.m
**	==========================
**
**	An anchor represents a region of a hypertext node which is linked to
**	another anchor in the same or a different node.
*/

#define ANCHOR_CURRENT_VERSION 0

#import <ctype.h>
#import <objc/Object.h>
// #import <objc/typedstream.h>
#import <appkit/appkit.h>
#import "Anchor.h"
#import "HTUtils.h"
#import "HTParse.h"
#import "HyperText.h"
#import "HyperManager.h"

@implementation Anchor

static HyperManager *manager;
static NSMutableArray * orphans;		// Grand list of all anchors with no parents
NSMutableArray * HTHistory;		// List of visited anchors

+ initialize
{
    orphans = [NSMutableArray array];
    HTHistory = [NSMutableArray array];
    [Anchor setVersion:ANCHOR_CURRENT_VERSION];
    return self;
}

+ setManager:aManager
{
    manager = aManager;
    return self;
}
//				Creation Methods
//				================
//
//	Do not use "new" by itself outside this module. In order to enforce
//	consistency, we insist that you furnish more information about the
//	anchor you are creating.
//

- (id) init
{
    if(self = [super init]) {
        DestAnchor = nil;
        Address = (char *)0;
        Sources = [NSMutableArray array];
        children = [NSMutableArray array];
        parent = nil;
    }
    return self;
}


//	Case insensitive string comparison
//	----------------------------------
// On entry,
//	s	Points to one string, null terminated
//	t	points to the other.
// On exit,
//	returns	YES if the strings are equivalent ignoring case
//		NO if they differ in more than  their case.
//
PRIVATE BOOL equivalent(const char * s, const char *t)
{
    for(;*s && *t; s++, t++) {
        if (toupper(*s) != toupper(*t)) return NO;
    }
    return toupper(*s)==toupper(*t);
}


//	Create new or find old sub-anchor
//	---------------------------------
//
//	This one is for a new anchor being edited into an existing
//	document. The parent anchor must already exist.

+ (Anchor *) newParent:(Anchor *)anAnchor tag:(const char *)tag
{
    NSArray * kids = anAnchor->children;
    int n = [kids count];
    int i;

    Anchor *instance;

    for(i=0; i<n; i++) {
	   instance = [kids objectAtIndex:i];
	   if (equivalent(instance->Address, tag)) {
	    if (TRACE) {
            NSLog(@"Sub-anchor %@ with name `%s' already exists.", instance, tag);
        }
	    return instance;
	   }
    }

    instance = [[Anchor alloc] init];
    if (TRACE) {
        NSLog(@"new Anchor %@ named `%s' is child of %p", instance, tag, anAnchor);
    }
    instance->parent = anAnchor;
    [instance->parent->children addObject:instance];
    StrAllocCopy(instance->Address, tag);
    return instance;
}


//	Create new or find old named anchor
//	-----------------------------------
//
//	This one is for a reference which is found in a document, and might
//	not be already loaded.
//	Note: You are not guarranteed a new anchor -- you might get an old one,
//	like with fonts.

+ newAddress:(const char *)anAddress;
{
    char * anc = HTParse(anAddress, "", PARSE_ANCHOR); // Anchor id specified?
    Anchor *instance;

//	If the node is a sub-anchor, we recursively load its parent.
//	Then we create a sub-anchor within than node.

    if (*anc) {
        char *nod = HTParse(anAddress, "",
		 PARSE_ACCESS|PARSE_HOST|PARSE_PATH|PARSE_PUNCTUATION);
        Anchor * foundParent = [Anchor newAddress:nod];
	free(nod);


	instance = [Anchor newParent:foundParent tag:anc];
    	free (anc);

//	If the node has no parent, we check in a list of such nodes to see
//	whether we have it.

    } else { /* Is not a sub anchor */
	int i;
	int n=[orphans count];
	free(anc);
	for(i=0; i<n; i++) {
	    instance = [orphans objectAtIndex:i];
	    if (equivalent(instance->Address, anAddress)) {
		if (TRACE) printf(
			"Anchor %p with address `%s' already exists.\n",
		    	instance, anAddress);
		return instance;
	    }
	}
    	instance = [Anchor new];
	if (TRACE) {
        NSLog(@"new Anchor %@ has address `%s'\n", instance, anAddress);
    }
    	StrAllocCopy(instance->Address, anAddress);
    	[orphans addObject:instance];
    }
    return instance;
}


//				Navigation	(Class methods)
//				==========
//
//		Go back in history
//		------------------
+back
{
    Anchor *anchor = [HTHistory lastObject];
    [HTHistory removeLastObject];
    return anchor;
}

//		Go to next logical step
//		-----------------------
//
//	We take the link After or before the one we took to get where we are
//
+moveBy:(int)offset
{
    Anchor * up = [HTHistory lastObject];
    if (up)
    if (up->parent){
        NSArray * kids = up->parent->children;
    	NSUInteger i = [kids indexOfObject:up];
	Anchor * nextOne =[kids objectAtIndex:i+offset];
	if (nextOne) {
	    [HTHistory removeLastObject];
	    [nextOne follow];
	} else {
	    if (TRACE) printf("Anchor: No such logical step\n");
	}
    }
    return self;
}

+next		{ return [self moveBy:+1]; }
+previous	{ return [self moveBy:-1]; }


//		Reorder the children
//		--------------------
//
//	This is necessary to ensure that an anchor which might have existed already
//	in fact is put in the correct order as we load the node.
//
- (void) isLastChild
{
    if(parent) {
        NSMutableArray * siblings = parent->children;
	   [siblings removeObject:self];
	   [siblings addObject:self];
    }
}


//
//		Free an anchor
//		--------------
- (void) free
{
    if (Address) free(Address);
    if (parent) [parent->children removeObject:self];
    if (TRACE) printf("Anchor: free called!  Not removed from Node!!!!!!!\n");
    [Sources makeObjectsPerformSelector:@selector(unload)];
    if (!parent) [orphans removeObject:self];
    return [super dealloc];
}

//	Get list of sources

- sources	{ return Sources; }

//	Return parent

- parent	{ return parent; }

//	Remove the reference from this anchor to an other
//
- unlink
{
    if (DestAnchor) {
    	(void) [(HyperText*)Node disconnectAnchor:self];	/* select */
	[[DestAnchor sources] removeObject:self];
	DestAnchor = nil;
    }
    return self;
}

//	For allowing dangling links, when things disappear

- unload
{
    DestAnchor = nil;		/* invalidate the pointer */
    return self;
}

//	This removes the anchor from the structure entirely, and frees it.
//
- (void) delete
{
    if (DestAnchor) [self unlink];		    // Remove outgoing link
    [Sources makeObjectsPerformSelector:@selector(unlink)]; // Remove incomming links
    return [self dealloc];
}

//	Set the region represented by the anchor
//
- (void) setNode: (id) node
{
    Node = node;
}




/*	Select the anchor						select
**	-----------------
**
**	This will load the node is necessary, if the anchor has only a network
**	address.
*/
- selectDiagnostic: (int) diag
{
    Anchor * nodeAnchor = parent ? parent : self;

    if (!nodeAnchor->Node) {		/* If the node is not loaded, */
	if (!nodeAnchor->Address) {
	    if (TRACE) printf(
	    	"Anchor %p: node not loaded, no address!\n", nodeAnchor);
	    return nil;
	} else {
	    if (![manager loadAnchor:nodeAnchor Diagnostic:diag]) {
		if (TRACE) printf("Anchor %p: Couldn't load node `%s'!\n",
			 nodeAnchor, nodeAnchor->Address);
		return nil;
	    }
	}
    }
    if (!nodeAnchor) return nil;			/* Failed */
    if (!nodeAnchor->Node) return nodeAnchor;		/* Ok, foreign */
    return [nodeAnchor->Node selectAnchor:self];	/* Ok, text */
}


/*	Select the anchor						select
**	-----------------
**
**	This will load the node is necessary, if the anchor has only a network
**	address.
*/
- select
{
    return [self selectDiagnostic:0];
}


//	Set reference string
- setAddress: (const char *) ref_string
{
   if (TRACE) printf("Anchor %p has address `%s'\n", self, ref_string);
   StrAllocCopy(Address, ref_string);
   return self;
}

//	Return the address of this anchor

- (const char *)address
{
    return Address;
}

//	Generate a malloc'd string for the FULL anchor address
//
- (char *)fullAddress
{
    char * result;
    if (parent) {
    	result = (char *) malloc(
		strlen(Address) + 1 + strlen([parent address])+ 1);
	strcpy(result, [parent address]);
	strcat(result, "#");
	strcat(result, Address);
    } else { /* no parent */
    	result = (char *) malloc(strlen(Address)+ 1);
	strcpy(result, Address);
    }
    return result;
}

//	Link this Anchor to another given one
//	-------------------------------------

- (void) linkTo:(Anchor *)destination;
{
    if (TRACE) printf(
    	"Anchor: Linking anchor %p to anchor %p\n", self, destination);
    DestAnchor = destination;
    [destination->Sources addObject:self];
}

//	Follow a link to its destination
//	--------------------------------
- (BOOL) follow;
{
    if (DestAnchor)
	if ([DestAnchor select]) {
	    if (TRACE) printf("Anchor: followed link from %p to %p\n",
	    						self, DestAnchor);
	    [HTHistory addObject:self];
	    return YES;
	}

    return NO;
}

//	Figure out the node from that of the parent

- node
{
	return parent ? [parent node] : Node;
}

- destination { return DestAnchor; }

@end
