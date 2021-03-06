//
//  PSMTabBarControl.m
//  PSMTabBarControl
//
//  Created by John Pannell on 10/13/05.
//  Copyright 2005 Positive Spin Media. All rights reserved.
//

#import "PSMTabBarControl.h"
#import "PSMTabBarCell.h"
#import "PSMOverflowPopUpButton.h"
#import "PSMRolloverButton.h"
#import "PSMTabStyle.h"
#import "PSMSequelProTabStyle.h"
#import "PSMTabDragAssistant.h"
#import "PSMTabBarController.h"
#include <Carbon/Carbon.h> /* for GetKeys() and KeyMap */
#include <bitstring.h>

#import "SPDatabaseDocument.h"
#import "sequel-ace-Swift.h"

@interface PSMTabBarControl (Private)

    // constructor/destructor
- (void)initAddedProperties;

    // accessors
- (NSEvent *)lastMouseDownEvent;
- (void)setLastMouseDownEvent:(NSEvent *)event;

    // contents
- (void)addTabViewItem:(NSTabViewItem *)item;
- (void)removeTabForCell:(PSMTabBarCell *)cell;

    // draw
- (void)_setupTrackingRectsForCell:(PSMTabBarCell *)cell;
- (void)_positionOverflowMenu;
- (void)_checkWindowFrame;
- (void)updateTabBarAndUpdateTabs:(BOOL)updateTabs;

    // actions
- (void)closeTabClick:(id)sender;

	// notification handlers
- (void)frameDidChange:(NSNotification *)notification;
- (void)windowDidMove:(NSNotification *)aNotification;
- (void)windowDidUpdate:(NSNotification *)notification;
- (void)windowStatusDidChange:(NSNotification *)notification;

    // NSTabView delegate
- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem;
- (BOOL)tabView:(NSTabView *)tabView shouldSelectTabViewItem:(NSTabViewItem *)tabViewItem;
- (void)tabView:(NSTabView *)tabView willSelectTabViewItem:(NSTabViewItem *)tabViewItem;
- (void)tabViewDidChangeNumberOfTabViewItems:(NSTabView *)tabView;

    // archiving
- (void)encodeWithCoder:(NSCoder *)aCoder;
- (instancetype)initWithCoder:(NSCoder *)aDecoder;

    // convenience
- (void)_bindPropertiesForCell:(PSMTabBarCell *)cell andTabViewItem:(NSTabViewItem *)item;
- (id)cellForPoint:(NSPoint)point cellFrame:(NSRectPointer)outFrame;
@end

@implementation PSMTabBarControl

#pragma mark -
#pragma mark Characteristics
+ (NSBundle *)bundle;
{
    static NSBundle *bundle = nil;
    if (!bundle) bundle = [NSBundle bundleForClass:[PSMTabBarControl class]];
    return bundle;
}

/*!
    @method     availableCellWidth
    @abstract   The number of pixels available for cells
    @discussion Calculates the number of pixels available for cells based on margins and the window resize badge.
    @returns    Returns the amount of space for cells.
*/

- (CGFloat)availableCellWidth
{
    return [self frame].size.width - [style leftMarginForTabBarControl] - [style rightMarginForTabBarControl] - _resizeAreaCompensation;
}

/*!
    @method     genericCellRect
    @abstract   The basic rect for a tab cell.
    @discussion Creates a generic frame for a tab cell based on the current control state.
    @returns    Returns a basic rect for a tab cell.
*/

- (NSRect)genericCellRect
{
    NSRect aRect=[self frame];
    aRect.origin.x = [style leftMarginForTabBarControl];
    aRect.origin.y = 0.0f;
    aRect.size.width = [self availableCellWidth];
    aRect.size.height = [style tabCellHeight];
    return aRect;
}

- (void)layout {
    [_addTabButton setUsualImage:[style addTabButtonImage]];
    
    [super layout];
}

#pragma mark -
#pragma mark Constructor/destructor

- (void)initAddedProperties
{
    _cells = [[NSMutableArray alloc] initWithCapacity:10];
	_controller = [[PSMTabBarController alloc] initWithTabBarControl:self];
	_lastWindowIsMainCheck = NO;
	_lastAttachedWindowIsMainCheck = NO;
	_lastAppIsActiveCheck = NO;
	_lastMouseDownEvent = nil;
	
    // default config
	_orientation = PSMTabBarHorizontalOrientation;
    _canCloseOnlyTab = NO;
	_disableTabClose = NO;
    _showAddTabButton = NO;
    _sizeCellsToFit = NO;
    _awakenedFromNib = NO;
    _useOverflowMenu = YES;
	_allowsBackgroundTabClosing = YES;
	_allowsResizing = NO;
	_selectsTabsOnMouseDown = NO;
    _alwaysShowActiveTab = NO;
	_allowsScrubbing = NO;
	_useSafariStyleDragging = NO;
    _cellMinWidth = 100;
    _cellMaxWidth = 280;
    _cellOptimumWidth = 130;
	_tearOffStyle = PSMTabBarTearOffAlphaWindow;
	
	style = [[PSMSequelProTabStyle alloc] init];
    
    // the overflow button/menu
    NSRect overflowButtonRect = NSMakeRect([self frame].size.width - [style rightMarginForTabBarControl] + 1, 0, [style rightMarginForTabBarControl] - 1, [self frame].size.height);
    _overflowPopUpButton = [[PSMOverflowPopUpButton alloc] initWithFrame:overflowButtonRect pullsDown:YES];
    [_overflowPopUpButton setAutoresizingMask:NSViewNotSizable | NSViewMinXMargin];
    [_overflowPopUpButton setHidden:YES];
    [self addSubview:_overflowPopUpButton];
    [self _positionOverflowMenu];
    
    // new tab button
    NSRect addTabButtonRect = NSMakeRect([self frame].size.width - [style rightMarginForTabBarControl] + 1, 3.0f, 16.0f, 16.0f);
    _addTabButton = [[PSMRolloverButton alloc] initWithFrame:addTabButtonRect];
	
    if (_addTabButton) {
        NSImage *newButtonImage = [style addTabButtonImage];
        if (newButtonImage) {
            [_addTabButton setUsualImage:newButtonImage];
        }
        [_addTabButton setTitle:@""];
        [_addTabButton setImagePosition:NSImageOnly];
        [_addTabButton setButtonType:NSMomentaryChangeButton];
        [_addTabButton setBordered:NO];
        [_addTabButton setBezelStyle:NSShadowlessSquareBezelStyle];
        [self addSubview:_addTabButton];
        
        if (_showAddTabButton) {
            [_addTabButton setHidden:NO];
        } else {
            [_addTabButton setHidden:YES];
        }
        [_addTabButton setNeedsDisplay:YES];
    }
}
    
- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization
        [self initAddedProperties];
        [self registerForDraggedTypes:@[@"PSMTabBarControlItemPBType"]];
		
		// resize
		[self setPostsFrameChangedNotifications:YES];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(frameDidChange:) name:NSViewFrameDidChangeNotification object:self];
    }
    [self setTarget:self];
    return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	//unbind all the items to prevent crashing
	//not sure if this is necessary or not
    NSArray *cells = [NSArray arrayWithArray:_cells];  // create a copy as we will change the original array while being enumerated
	NSEnumerator *enumerator = [cells objectEnumerator];
	PSMTabBarCell *nextCell;
	while ( (nextCell = [enumerator nextObject]) ) {
		[self removeTabForCell:nextCell];
	}
    
    [self unregisterDraggedTypes];
}

- (void)awakeFromNib
{
    // build cells from existing tab view items
    NSArray *existingItems = [tabView tabViewItems];
    NSEnumerator *e = [existingItems objectEnumerator];
    NSTabViewItem *item;
    while ( (item = [e nextObject]) ) {
        if (![[self representedTabViewItems] containsObject:item]) {
            [self addTabViewItem:item];
		}
    }
}

- (void)viewWillMoveToWindow:(NSWindow *)aWindow {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	
	[center removeObserver:self name:NSWindowDidBecomeMainNotification object:nil];
	[center removeObserver:self name:NSWindowDidResignMainNotification object:nil];
	[center removeObserver:self name:NSWindowDidUpdateNotification object:nil];
	[center removeObserver:self name:NSWindowDidMoveNotification object:nil];
	
    if (aWindow) {
		[center addObserver:self selector:@selector(windowStatusDidChange:) name:NSWindowDidBecomeMainNotification object:aWindow];
		[center addObserver:self selector:@selector(windowStatusDidChange:) name:NSWindowDidResignMainNotification object:aWindow];
		[center addObserver:self selector:@selector(windowDidUpdate:) name:NSWindowDidUpdateNotification object:aWindow];
		[center addObserver:self selector:@selector(windowDidMove:) name:NSWindowDidMoveNotification object:aWindow];
    }
}

/**
 * Allow a window to be redrawn in response to changes in position or focus level.
 */
- (void)windowStatusDidChange:(NSNotification *)notification
{
	[self setNeedsDisplay:YES];
}

#pragma mark -
#pragma mark Accessors

- (NSMutableArray *)cells
{
    return _cells;
}

- (NSEvent *)lastMouseDownEvent
{
    return _lastMouseDownEvent;
}

- (void)setLastMouseDownEvent:(NSEvent *)event
{
    _lastMouseDownEvent = event;
}

- (id)delegate
{
    return delegate;
}

- (void)setDelegate:(id)object
{
    delegate = object;
	
	NSMutableArray *types = [NSMutableArray arrayWithObjects:@"PSMTabBarControlItemPBType", NSStringPboardType,nil];
	
	//Update the allowed drag types
	if ([self delegate] && [[self delegate] respondsToSelector:@selector(allowedDraggedTypesForTabView:)]) {
		[types addObjectsFromArray:[[self delegate] allowedDraggedTypesForTabView:tabView]];
	}
	[self unregisterDraggedTypes];
	[self registerForDraggedTypes:types];
}

- (NSTabView *)tabView
{
    return tabView;
}

- (void)setTabView:(NSTabView *)view
{
    tabView = view;
}

- (id<PSMTabStyle>)style
{
    return style;
}

- (NSString *)styleName
{
    return [style name];
}

- (void)setStyle:(id <PSMTabStyle>)newStyle
{
    if (style != newStyle) {
        style = newStyle;
        
        // restyle add tab button
        if (_addTabButton) {
            NSImage *newButtonImage = [style addTabButtonImage];
            if (newButtonImage) {
                [_addTabButton setUsualImage:newButtonImage];
            }
        }
        
        [self update];
    }
}

- (void)setStyleNamed:(NSString *)name
{
    id <PSMTabStyle> newStyle;

    if ([name isEqualToString:@"SequelPro"]) {
		newStyle = [[PSMSequelProTabStyle alloc] init];
	}
	else {
		newStyle = [[PSMSequelProTabStyle alloc] init];
	}

    [self setStyle:newStyle];
}

- (PSMTabBarOrientation)orientation
{
	return _orientation;
}

- (void)setOrientation:(PSMTabBarOrientation)value
{
	PSMTabBarOrientation lastOrientation = _orientation;
	_orientation = value;

	if (_tabBarWidth < 10) {
		_tabBarWidth = 120;
	}
	
	if (lastOrientation != _orientation) {
		[[self style] setOrientation:_orientation];

        [self _positionOverflowMenu]; //move the overflow popup button to the right place
		[self update];
	}
}

- (BOOL)canCloseOnlyTab
{
    return _canCloseOnlyTab;
}

- (void)setCanCloseOnlyTab:(BOOL)value
{
    _canCloseOnlyTab = value;
    if ([_cells count] == 1) {
        [self update];
    }
}

- (BOOL)disableTabClose
{
	return _disableTabClose;
}

- (void)setDisableTabClose:(BOOL)value
{
	_disableTabClose = value;
	[self update];
}

- (BOOL)showAddTabButton
{
    return _showAddTabButton;
}

- (void)setShowAddTabButton:(BOOL)value
{
    _showAddTabButton = value;
	if (!NSIsEmptyRect([_controller addButtonRect]))
		[_addTabButton setFrame:[_controller addButtonRect]];

    [_addTabButton setHidden:!_showAddTabButton];
	[_addTabButton setNeedsDisplay:YES];

	[self update];
}

- (id)createNewTabTarget
{	
	return _createNewTabTarget;
}

- (void)setCreateNewTabTarget:(id)object
{
	_createNewTabTarget = object;
	[[self addTabButton] setTarget:object];
}

- (SEL)createNewTabAction
{
	return _createNewTabAction;	
}

- (void)setCreateNewTabAction:(SEL)selector
{
	_createNewTabAction = selector;
	[[self addTabButton] setAction:selector];
}

- (id)doubleClickTarget
{	
	return _doubleClickTarget;
}

- (void)setDoubleClickTarget:(id)object
{
	_doubleClickTarget = object;
}

- (SEL)doubleClickAction
{
	return _doubleClickAction;	
}

- (void)setDoubleClickAction:(SEL)selector
{
	_doubleClickAction = selector;
}

- (NSInteger)cellMinWidth
{
    return _cellMinWidth;
}

- (void)setCellMinWidth:(NSInteger)value
{
    _cellMinWidth = value;
    [self update];
}

- (NSInteger)cellMaxWidth
{
    return _cellMaxWidth;
}

- (void)setCellMaxWidth:(NSInteger)value
{
    _cellMaxWidth = value;
    [self update];
}

- (NSInteger)cellOptimumWidth
{
    return _cellOptimumWidth;
}

- (void)setCellOptimumWidth:(NSInteger)value
{
    _cellOptimumWidth = value;
    [self update];
}

- (BOOL)sizeCellsToFit
{
    return _sizeCellsToFit;
}

- (void)setSizeCellsToFit:(BOOL)value
{
    _sizeCellsToFit = value;
    [self update];
}

- (BOOL)useOverflowMenu
{
    return _useOverflowMenu;
}

- (void)setUseOverflowMenu:(BOOL)value
{
    _useOverflowMenu = value;
    [self update];
}

- (PSMRolloverButton *)addTabButton
{
    return _addTabButton;
}

- (PSMOverflowPopUpButton *)overflowPopUpButton
{
    return _overflowPopUpButton;
}

- (BOOL)allowsBackgroundTabClosing
{
	return _allowsBackgroundTabClosing;
}

- (void)setAllowsBackgroundTabClosing:(BOOL)value
{
	_allowsBackgroundTabClosing = value;
}

- (BOOL)allowsResizing
{
	return _allowsResizing;
}

- (void)setAllowsResizing:(BOOL)value
{
	_allowsResizing = value;
}

- (BOOL)selectsTabsOnMouseDown
{
	return _selectsTabsOnMouseDown;
}

- (void)setSelectsTabsOnMouseDown:(BOOL)value
{
	_selectsTabsOnMouseDown = value;
}

- (BOOL)createsTabOnDoubleClick;
{
	return _createsTabOnDoubleClick;
}

- (void)setCreatesTabOnDoubleClick:(BOOL)value
{
	_createsTabOnDoubleClick = value;
}

- (BOOL)alwaysShowActiveTab
{
	return _alwaysShowActiveTab;
}

- (void)setAlwaysShowActiveTab:(BOOL)value
{
	_alwaysShowActiveTab = value;
}

- (BOOL)allowsScrubbing
{
	return _allowsScrubbing;
}

- (void)setAllowsScrubbing:(BOOL)value
{
	_allowsScrubbing = value;
}

- (BOOL)usesSafariStyleDragging
{
	return _useSafariStyleDragging;
}

- (void)setUsesSafariStyleDragging:(BOOL)value
{
	_useSafariStyleDragging = value;
}

- (PSMTabBarTearOffStyle)tearOffStyle
{
	return _tearOffStyle;
}

- (void)setTearOffStyle:(PSMTabBarTearOffStyle)tearOffStyle
{
	_tearOffStyle = tearOffStyle;
}

#pragma mark -
#pragma mark Functionality

- (void)addTabViewItem:(NSTabViewItem *)item
{
    // create cell
    PSMTabBarCell *cell = [[PSMTabBarCell alloc] initWithControlView:self];
	NSRect cellRect, lastCellFrame = [[_cells lastObject] frame];
	
	if ([self orientation] == PSMTabBarHorizontalOrientation) {
		cellRect = [self genericCellRect];
		cellRect.size.width = 30;
		cellRect.origin.x = lastCellFrame.origin.x + lastCellFrame.size.width;
	} else {
		cellRect = /*lastCellFrame*/[self genericCellRect];
		cellRect.size.width = lastCellFrame.size.width;
		cellRect.size.height = 0;
		cellRect.origin.y = lastCellFrame.origin.y + lastCellFrame.size.height;
	}
	
    [cell setRepresentedObject:item];
	[cell setFrame:cellRect];
    
    // bind it up
    [self bindPropertiesForCell:cell andTabViewItem:item];
	
    // add to collection
    [_cells addObject:cell];
    if ((NSInteger)[_cells count] == [tabView numberOfTabViewItems]) {
        [self update]; // don't update unless all are accounted for!
	}
}

- (void)removeTabForCell:(PSMTabBarCell *)cell {
	NSTabViewItem *item = [cell representedObject];
	
    // unbind
    [[cell indicator] unbind:@"animate"];
    [[cell indicator] unbind:@"hidden"];
    [cell unbind:@"hasIcon"];
    [cell unbind:@"hasLargeImage"];
    [cell unbind:@"title"];
    [cell unbind:@"count"];
	[cell unbind:@"countColor"];
    [cell unbind:@"isEdited"];

    SPDatabaseDocument *databaseDocument = [item databaseDocument];

	if (databaseDocument) {
		if ([databaseDocument respondsToSelector:@selector(isProcessing)]) {
			[databaseDocument removeObserver:cell forKeyPath:@"isProcessing"];
		}
		if ([databaseDocument respondsToSelector:@selector(icon)]) {
			[databaseDocument removeObserver:cell forKeyPath:@"icon"];
		}
		if ([databaseDocument respondsToSelector:@selector(count)]) {
			[databaseDocument removeObserver:cell forKeyPath:@"objectCount"];
		}
		if ([databaseDocument respondsToSelector:@selector(countColor)]) {
			[databaseDocument removeObserver:cell forKeyPath:@"countColor"];
		}
		if ([databaseDocument respondsToSelector:@selector(largeImage)]) {
			[databaseDocument removeObserver:cell forKeyPath:@"largeImage"];
		}
		if ([databaseDocument respondsToSelector:@selector(isEdited)]) {
			[databaseDocument removeObserver:cell forKeyPath:@"isEdited"];
		}
	}
	
    // stop watching identifier
    [item removeObserver:self forKeyPath:@"identifier"];
    
    // remove indicator
    if ([[self subviews] containsObject:[cell indicator]]) {
        [[cell indicator] removeFromSuperview];
    }
    if(cell != nil){
        // remove tracking
        [[NSNotificationCenter defaultCenter] removeObserver:cell];

        if ([cell closeButtonTrackingTag] != 0) {
            [self removeTrackingRect:[cell closeButtonTrackingTag]];
            [cell setCloseButtonTrackingTag:0];
        }
        if ([cell cellTrackingTag] != 0) {
            [self removeTrackingRect:[cell cellTrackingTag]];
            [cell setCellTrackingTag:0];
        }

        // pull from collection
        [_cells removeObject:cell];
    }
    else{
        SPLog(@"cell is nil");
    }

    [self update];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    // did the tab's identifier change?
    if ([keyPath isEqualToString:@"identifier"]) {
        NSEnumerator *e = [_cells objectEnumerator];
        PSMTabBarCell *cell;
        while ( (cell = [e nextObject]) ) {
            if ([cell representedObject] == object) {
                [self _bindPropertiesForCell:cell andTabViewItem:object];
			}
        }
    } else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

#pragma mark -
#pragma mark Hide/Show

- (void)updateTabs {
    if (!_awakenedFromNib) {
        return;
	}
	
    [[self subviews] makeObjectsPerformSelector:@selector(removeFromSuperview)];

    [self addSubview:_overflowPopUpButton];
    [self addSubview:_addTabButton];

    CGFloat partnerOriginalSize, partnerOriginalOrigin, myOriginalSize, myOriginalOrigin, partnerTargetSize, partnerTargetOrigin, myTargetSize, myTargetOrigin;
    
    // target values for partner
    if ([self orientation] == PSMTabBarHorizontalOrientation) {
		// current (original) values
		myOriginalSize = [self frame].size.height;
		myOriginalOrigin = [self frame].origin.y;
		if (partnerView) {
			partnerOriginalSize = [partnerView frame].size.height;
			partnerOriginalOrigin = [partnerView frame].origin.y;
		} else {
			partnerOriginalSize = [[self window] frame].size.height;
			partnerOriginalOrigin = [[self window] frame].origin.y;
		}
        myTargetSize = kPSMTabBarControlHeight;

		if (partnerView) {
			partnerTargetSize = partnerOriginalSize + myOriginalSize - myTargetSize;

			// above or below me?
			if ((myOriginalOrigin - kPSMTabBarControlHeight) > partnerOriginalOrigin) {

				// partner is below me, keeps its origin
				partnerTargetOrigin = partnerOriginalOrigin;
				myTargetOrigin = myOriginalOrigin + myOriginalSize - myTargetSize;
			} else {

				// partner is above me, I keep my origin
				myTargetOrigin = myOriginalOrigin;
				partnerTargetOrigin = partnerOriginalOrigin + myOriginalSize - myTargetSize;
			}
		} else {

			// for window movement
			myTargetOrigin = myOriginalOrigin;
			partnerTargetOrigin = partnerOriginalOrigin + myOriginalSize - myTargetSize;
			partnerTargetSize = partnerOriginalSize - myOriginalSize + myTargetSize;
		}
	} else /* vertical */ {
		// current (original) values
		myOriginalSize = [self frame].size.width;
		myOriginalOrigin = [self frame].origin.x;
		if (partnerView) {
			partnerOriginalSize = [partnerView frame].size.width;
			partnerOriginalOrigin = [partnerView frame].origin.x;
		} else {
			partnerOriginalSize = [[self window] frame].size.width;
			partnerOriginalOrigin = [[self window] frame].origin.x;
		}
		
		if (partnerView) {
			//to the left or right?
			if (myOriginalOrigin < partnerOriginalOrigin + partnerOriginalSize) {
                // partner is to the left
					// I'm growing
					myTargetOrigin = myOriginalOrigin;
					myTargetSize = myOriginalSize + _tabBarWidth;
					partnerTargetOrigin = partnerOriginalOrigin + _tabBarWidth;
					partnerTargetSize = partnerOriginalSize - _tabBarWidth;
			} else {
				// partner is to the right
					// I'm growing
					myTargetOrigin = myOriginalOrigin - _tabBarWidth;
					myTargetSize = myOriginalSize + _tabBarWidth;
					partnerTargetOrigin = partnerOriginalOrigin;
					partnerTargetSize = partnerOriginalSize - _tabBarWidth;
			}
		} else {
				// I'm growing
				myTargetOrigin = myOriginalOrigin;
				myTargetSize = _tabBarWidth;
				partnerTargetOrigin = partnerOriginalOrigin - _tabBarWidth + 1;
				partnerTargetSize = partnerOriginalSize + _tabBarWidth - 1;
		}
		
        if ([[self delegate] respondsToSelector:@selector(desiredWidthForVerticalTabBar:)]) {
			myTargetSize = [[self delegate] desiredWidthForVerticalTabBar:self];
        }
	}

    // moves the frame of the tab bar and window (or partner view) linearly to hide or show the tab bar
    NSRect myFrame = [self frame];
    CGFloat myCurrentOrigin = (myOriginalOrigin + ((myTargetOrigin - myOriginalOrigin)));
    CGFloat myCurrentSize = (myOriginalSize + ((myTargetSize - myOriginalSize)));
    CGFloat partnerCurrentOrigin = (partnerOriginalOrigin + ((partnerTargetOrigin - partnerOriginalOrigin)));
    CGFloat partnerCurrentSize = (partnerOriginalSize + ((partnerTargetSize - partnerOriginalSize)));
    
	NSRect myNewFrame;
	if ([self orientation] == PSMTabBarHorizontalOrientation) {
		myNewFrame = NSMakeRect(myFrame.origin.x, myCurrentOrigin, myFrame.size.width, myCurrentSize);
	} else {
		myNewFrame = NSMakeRect(myCurrentOrigin, myFrame.origin.y, myCurrentSize, myFrame.size.height);
	}
    
    if (partnerView) {
        // resize self and view
		NSRect resizeRect;
        if ([self orientation] == PSMTabBarHorizontalOrientation) {
			resizeRect = NSMakeRect([partnerView frame].origin.x, partnerCurrentOrigin, [partnerView frame].size.width, partnerCurrentSize);
		} else {
			resizeRect = NSMakeRect(partnerCurrentOrigin, [partnerView frame].origin.y, partnerCurrentSize, [partnerView frame].size.height);
		}
		[partnerView setFrame:resizeRect];
        [partnerView setNeedsDisplay:YES];
        [self setFrame:myNewFrame];
    } else {
        // resize self and window
		NSRect resizeRect;
        if ([self orientation] == PSMTabBarHorizontalOrientation) {
			resizeRect = NSMakeRect([[self window] frame].origin.x, partnerCurrentOrigin, [[self window] frame].size.width, partnerCurrentSize);
		} else {
			resizeRect = NSMakeRect(partnerCurrentOrigin, [[self window] frame].origin.y, partnerCurrentSize, [[self window] frame].size.height);
		}
        [[self window] setFrame:resizeRect display:YES];
        [self setFrame:myNewFrame];
    }
    
    [self viewDidEndLiveResize];
    [self update];
    if ([self delegate] && [[self delegate] respondsToSelector:@selector(tabView:tabBarDidUnhide:)]) {
        [[self delegate] tabView:[self tabView] tabBarDidUnhide:self];
    }
    [[self window] display];
}

- (id)partnerView
{
    return partnerView;
}

- (void)setPartnerView:(id)view
{
    partnerView = view;
}

#pragma mark -
#pragma mark Drawing

- (BOOL)isFlipped
{
    return YES;
}

- (void)drawRect:(NSRect)rect 
{
    [style drawTabBar:self inRect:rect];
}

- (void)update
{
	[self updateTabBarAndUpdateTabs:YES];
}

- (void)updateTabBarAndUpdateTabs:(BOOL)updateTabs
{
    // make sure all of our tabs are accounted for before updating,
	// or only proceed if a drag is in progress (where counts may mismatch)
    if ([[self tabView] numberOfTabViewItems] != (NSInteger)[_cells count] && ![[PSMTabDragAssistant sharedDragAssistant] isDragging]) {
        return;
    }

	if (updateTabs) {
        [self updateTabs];
	}
	
    [self removeAllToolTips];
    [_controller layoutCells]; //eventually we should only have to call this when we know something has changed
    
    PSMTabBarCell *currentCell;
    
    NSMenu *overflowMenu = [_controller overflowMenu];
    [_overflowPopUpButton setHidden:(overflowMenu == nil)];
    [_overflowPopUpButton setMenu:overflowMenu];

    for (NSUInteger i = 0; i < [_cells count]; i++) {
        currentCell = [_cells objectAtIndex:i];
        [currentCell setFrame:[_controller cellFrameAtIndex:i]];
        
        if (![currentCell isInOverflowMenu]) {
            [self _setupTrackingRectsForCell:currentCell];
        }
    }
    
    [_addTabButton setFrame:[_controller addButtonRect]];
    [_addTabButton setHidden:!_showAddTabButton];
    [self setNeedsDisplay:YES];
}

- (void)_setupTrackingRectsForCell:(PSMTabBarCell *)cell
{

	// Skip tracking rects for placeholders - not required.
	if ([cell isPlaceholder]) return;

    NSInteger tag;
	NSUInteger anIndex = [_cells indexOfObject:cell];
    NSRect cellTrackingRect = [_controller cellTrackingRectAtIndex:anIndex];
    NSPoint mousePoint = [self convertPoint:[[self window] mouseLocationOutsideOfEventStream] fromView:nil];
    BOOL mouseInCell = NSMouseInRect(mousePoint, cellTrackingRect, [self isFlipped]);

	// If dragging, suppress mouse interaction
	if ([[PSMTabDragAssistant sharedDragAssistant] isDragging]) mouseInCell = NO;

    //set the cell tracking rect
    [self removeTrackingRect:[cell cellTrackingTag]];
    tag = [self addTrackingRect:cellTrackingRect owner:cell userData:nil assumeInside:mouseInCell];
    [cell setCellTrackingTag:tag];
    [cell setHighlighted:mouseInCell];
    
    if ([cell hasCloseButton] && ![cell isCloseButtonSuppressed]) {
        NSRect closeRect = [_controller closeButtonTrackingRectAtIndex:anIndex];
        BOOL mouseInCloseRect = NSMouseInRect(mousePoint, closeRect, [self isFlipped]);
        
        //set the close button tracking rect
        [self removeTrackingRect:[cell closeButtonTrackingTag]];
        tag = [self addTrackingRect:closeRect owner:cell userData:nil assumeInside:mouseInCloseRect];
        [cell setCloseButtonTrackingTag:tag];
    }
    
    //set the tooltip tracking rect
    [self addToolTipRect:[cell frame] owner:self userData:nil];
}

- (void)_positionOverflowMenu
{
    NSRect cellRect, frame = [self frame];
    cellRect.size.height = [style tabCellHeight];
    cellRect.size.width = [style rightMarginForTabBarControl];
    
	if ([self orientation] == PSMTabBarHorizontalOrientation) {
		cellRect.origin.y = 0;
		cellRect.origin.x = frame.size.width - [style rightMarginForTabBarControl] + (_resizeAreaCompensation ? -(_resizeAreaCompensation - 1) : 1);
		[_overflowPopUpButton setAutoresizingMask:NSViewNotSizable | NSViewMinXMargin];
	} else {
		cellRect.origin.x = 0;
		cellRect.origin.y = frame.size.height - [style tabCellHeight];
		cellRect.size.width = frame.size.width;
		[_overflowPopUpButton setAutoresizingMask:NSViewNotSizable | NSViewMinXMargin | NSViewMinYMargin];
	}
	
    [_overflowPopUpButton setFrame:cellRect];
}

- (void)_checkWindowFrame
{
	//figure out if the new frame puts the control in the way of the resize widget
	NSWindow *window = [self window];
	
	if (window) {
		NSRect resizeWidgetFrame = [[window contentView] frame];
		resizeWidgetFrame.origin.x += resizeWidgetFrame.size.width - 22;
		resizeWidgetFrame.size.width = 22;
		resizeWidgetFrame.size.height = 22;
		
		if ([window showsResizeIndicator] && NSIntersectsRect([self frame], resizeWidgetFrame)) {
			//the resize widgets are larger on metal windows
			_resizeAreaCompensation = [window styleMask] & NSWindowStyleMaskTexturedBackground ? 20 : 8;
		} else {
			_resizeAreaCompensation = 0;
		}
		
		[self _positionOverflowMenu];
	}
}

#pragma mark -
#pragma mark Mouse Tracking

- (BOOL)mouseDownCanMoveWindow
{
    return NO;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent
{
    return YES;
}

- (void)mouseDown:(NSEvent *)theEvent
{
	_didDrag = NO;
	
    // keep for dragging
    [self setLastMouseDownEvent:theEvent];
    // what cell?
    NSPoint mousePt = [self convertPoint:[theEvent locationInWindow] fromView:nil];
	NSRect frame = [self frame];
	
	if ([self orientation] == PSMTabBarVerticalOrientation && [self allowsResizing] && partnerView && (mousePt.x > frame.size.width - 3)) {
		_resizing = YES;
	}
	
    NSRect cellFrame;
    PSMTabBarCell *cell = [self cellForPoint:mousePt cellFrame:&cellFrame];
    if (cell) {
		BOOL overClose = NSMouseInRect(mousePt, [cell closeButtonRectForFrame:cellFrame], [self isFlipped]);
        if (overClose && 
			![self disableTabClose] && 
			![cell isCloseButtonSuppressed] &&
			([self allowsBackgroundTabClosing] || [[cell representedObject] isEqualTo:[tabView selectedTabViewItem]] || [theEvent modifierFlags] & NSEventModifierFlagCommand)) {
			_closeClicked = YES;
		}
		else if ([theEvent clickCount] == 2) {
			[_doubleClickTarget performSelector:_doubleClickAction withObject:cell];
        } else if (_selectsTabsOnMouseDown) {
			[self performSelector:@selector(tabClick:) withObject:cell];
        }
        [self setNeedsDisplay:YES];
    } else {
		if ([theEvent clickCount] == 2) {
			// fire create new tab
			if ([self createsTabOnDoubleClick] && [self createNewTabTarget] != nil && [self createNewTabAction] != nil) {
				[[self createNewTabTarget] performSelector:[self createNewTabAction]];
			}
			return;
		}
	}
}

- (void)mouseDragged:(NSEvent *)theEvent
{
    if (![self lastMouseDownEvent]) {
        return;
    }
    
	NSPoint currentPoint = [self convertPoint:[theEvent locationInWindow] fromView:nil];
	
	if (_resizing) { 
		NSRect frame = [self frame];
		CGFloat resizeAmount = [theEvent deltaX];
		if ((currentPoint.x > frame.size.width && resizeAmount > 0) || (currentPoint.x < frame.size.width && resizeAmount < 0)) {
			[[NSCursor resizeLeftRightCursor] push];
			
			NSRect partnerFrame = [partnerView frame];
			
			//do some bounds checking
			if ((frame.size.width + resizeAmount > [self cellMinWidth]) && (frame.size.width + resizeAmount < [self cellMaxWidth])) {
				frame.size.width += resizeAmount;
				partnerFrame.size.width -= resizeAmount;
				partnerFrame.origin.x += resizeAmount;
				
				[self setFrame:frame];
				[partnerView setFrame:partnerFrame];
				[[self superview] setNeedsDisplay:YES];
			}	
		}
		return;
	}
	
    NSRect cellFrame;
    NSPoint trackingStartPoint = [self convertPoint:[[self lastMouseDownEvent] locationInWindow] fromView:nil];
    PSMTabBarCell *cell = [self cellForPoint:trackingStartPoint cellFrame:&cellFrame];
    if (cell) {
		//check to see if the close button was the target in the clicked cell
		//highlight/unhighlight the close button as necessary
		NSRect iconRect = [cell closeButtonRectForFrame:cellFrame];
		
		if (_closeClicked && NSMouseInRect(trackingStartPoint, iconRect, [self isFlipped]) &&
				([self allowsBackgroundTabClosing] || [[cell representedObject] isEqualTo:[tabView selectedTabViewItem]])) {
			[self setNeedsDisplay:YES];
			return;
		}
		
		CGFloat dx = fabs(currentPoint.x - trackingStartPoint.x);
		CGFloat dy = fabs(currentPoint.y - trackingStartPoint.y);
		CGFloat distance = sqrtf(dx * dx + dy * dy);
		
		if (distance >= 10 && !_didDrag && ![[PSMTabDragAssistant sharedDragAssistant] isDragging] &&
				[self delegate] && [[self delegate] respondsToSelector:@selector(tabView:shouldDragTabViewItem:fromTabBar:)] &&
				[[self delegate] tabView:tabView shouldDragTabViewItem:[cell representedObject] fromTabBar:self]) {
			_didDrag = YES;
			[[PSMTabDragAssistant sharedDragAssistant] startDraggingCell:cell fromTabBar:self withMouseDownEvent:[self lastMouseDownEvent]];
		}
	}
}

- (void)mouseUp:(NSEvent *)theEvent
{
	if (![self lastMouseDownEvent]) {
		return;
	}

	if (_resizing) {
		_resizing = NO;
		[[NSCursor arrowCursor] set];
	} else {
		// what cell?
		NSPoint mousePt = [self convertPoint:[theEvent locationInWindow] fromView:nil];
		NSRect cellFrame, mouseDownCellFrame;
		PSMTabBarCell *cell = [self cellForPoint:mousePt cellFrame:&cellFrame];
		PSMTabBarCell *mouseDownCell = [self cellForPoint:[self convertPoint:[[self lastMouseDownEvent] locationInWindow] fromView:nil] cellFrame:&mouseDownCellFrame];
		if (cell) {
			NSPoint trackingStartPoint = [self convertPoint:[[self lastMouseDownEvent] locationInWindow] fromView:nil];
			NSRect iconRect = [mouseDownCell closeButtonRectForFrame:mouseDownCellFrame];
			
			if ((NSMouseInRect(mousePt, iconRect,[self isFlipped])) && ![self disableTabClose] && ![cell isCloseButtonSuppressed]) {
				if (([[NSApp currentEvent] modifierFlags] & NSEventModifierFlagOption) != 0) {
					//If the user is holding Option, close all other tabs
					NSEnumerator	*enumerator = [[[self cells] copy] objectEnumerator];
					PSMTabBarCell	*otherCell;
					
					while ((otherCell = [enumerator nextObject])) {
						if (otherCell != cell)
							[self performSelector:@selector(closeTabClick:) withObject:otherCell];
					}
				} else {
					//Otherwise, close this tab
					[self performSelector:@selector(closeTabClick:) withObject:cell];
				}

			} else if (NSMouseInRect(mousePt, mouseDownCellFrame, [self isFlipped]) &&
					   (!NSMouseInRect(trackingStartPoint, [cell closeButtonRectForFrame:cellFrame], [self isFlipped]) || ![self allowsBackgroundTabClosing] || [self disableTabClose])) {
				// If -[self selectsTabsOnMouseDown] is TRUE, we already performed tabClick: on mouseDown.
				if (![self selectsTabsOnMouseDown]) {
					[self performSelector:@selector(tabClick:) withObject:cell];
				}

			}
		}
		
		_closeClicked = NO;
	}

	// Clear the last mouse down event to prevent drag issues
	[self setLastMouseDownEvent:nil];
}

- (NSMenu *)menuForEvent:(NSEvent *)event
{
	NSMenu *menu = nil;
	NSTabViewItem *item = [[self cellForPoint:[self convertPoint:[event locationInWindow] fromView:nil] cellFrame:nil] representedObject];
	
	if (item && [[self delegate] respondsToSelector:@selector(tabView:menuForTabViewItem:)]) {
		menu = [[self delegate] tabView:tabView menuForTabViewItem:item];
	}
	return menu;
}

#pragma mark -
#pragma mark Drag and Drop

- (BOOL)shouldDelayWindowOrderingForEvent:(NSEvent *)theEvent
{
    return YES;
}

// NSDraggingSource

- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context{
		
	return (context == NSDraggingContextWithinApplication ? NSDragOperationMove : NSDragOperationNone);
}

- (BOOL)ignoreModifierKeysForDraggingSession:(NSDraggingSession *)session{
	return YES;
}

- (void)draggingSession:(NSDraggingSession *)session willBeginAtPoint:(NSPoint)screenPoint{
	[[PSMTabDragAssistant sharedDragAssistant] draggingBeganAt:screenPoint];
}

- (void)draggingSession:(NSDraggingSession *)session movedToPoint:(NSPoint)screenPoint{
	[[PSMTabDragAssistant sharedDragAssistant] draggingMovedTo:screenPoint];

}

// NSDraggingDestination
- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
    if([[[sender draggingPasteboard] types] indexOfObject:@"PSMTabBarControlItemPBType"] != NSNotFound) {
        
        if ([self delegate] && [[self delegate] respondsToSelector:@selector(tabView:shouldDropTabViewItem:inTabBar:)] &&
				![[self delegate] tabView:[[sender draggingSource] tabView] shouldDropTabViewItem:[[[PSMTabDragAssistant sharedDragAssistant] draggedCell] representedObject] inTabBar:self]) {
			return NSDragOperationNone;
		}
        
        [[PSMTabDragAssistant sharedDragAssistant] draggingEnteredTabBar:self atPoint:[self convertPoint:[sender draggingLocation] fromView:nil]];
        return NSDragOperationMove;
    }
        
    return NSDragOperationNone;
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender
{
	
    if ([[[sender draggingPasteboard] types] indexOfObject:@"PSMTabBarControlItemPBType"] != NSNotFound) {
        
		if ([self delegate] && [[self delegate] respondsToSelector:@selector(tabView:shouldDropTabViewItem:inTabBar:)] &&
				![[self delegate] tabView:[[sender draggingSource] tabView] shouldDropTabViewItem:[[[PSMTabDragAssistant sharedDragAssistant] draggedCell] representedObject] inTabBar:self]) {
			return NSDragOperationNone;
		}
		
        [[PSMTabDragAssistant sharedDragAssistant] draggingUpdatedInTabBar:self atPoint:[self convertPoint:[sender draggingLocation] fromView:nil]];
        return NSDragOperationMove;
    }

	PSMTabBarCell *cell = [self cellForPoint:[self convertPoint:[sender draggingLocation] fromView:nil] cellFrame:nil];
	if (cell) {
		//something that was accepted by the delegate was dragged on

		// Notify the delegate to respond to drag events if supported.  This allows custom
		// behaviour when dragging certain drag types onto the tab - for example changing the
		// view appropriately.
		if ([self delegate] && [[self delegate] respondsToSelector:@selector(draggingEvent:enteredTabBar:tabView:)]) {
			[[self delegate] draggingEvent:sender enteredTabBar:self tabView:[cell representedObject]];
		}
		return NSDragOperationCopy;
	}
        
    return NSDragOperationNone;
}

- (void)draggingExited:(id <NSDraggingInfo>)sender
{

    [[PSMTabDragAssistant sharedDragAssistant] draggingExitedTabBar:self];
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender
{
	//validate the drag operation only if there's a valid tab bar to drop into
	return [[[sender draggingPasteboard] types] indexOfObject:@"PSMTabBarControlItemPBType"] == NSNotFound ||
				[[PSMTabDragAssistant sharedDragAssistant] destinationTabBar] != nil;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
	if ([[[sender draggingPasteboard] types] indexOfObject:@"PSMTabBarControlItemPBType"] != NSNotFound) {
		[[PSMTabDragAssistant sharedDragAssistant] performDragOperation];
	} else if ([self delegate] && [[self delegate] respondsToSelector:@selector(tabView:acceptedDraggingInfo:onTabViewItem:)]) {
		//forward the drop to the delegate
		[[self delegate] tabView:tabView acceptedDraggingInfo:sender onTabViewItem:[[self cellForPoint:[self convertPoint:[sender draggingLocation] fromView:nil] cellFrame:nil] representedObject]];
	}
    return YES;
}

- (void)draggingSession:(NSDraggingSession *)session
		   endedAtPoint:(NSPoint)screenPoint
			  operation:(NSDragOperation)operation{
	
	[[PSMTabDragAssistant sharedDragAssistant] draggedImageEndedAt:screenPoint operation:operation];
}

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender
{
}

#pragma mark -
#pragma mark Actions

- (void)overflowMenuAction:(id)sender
{
	NSTabViewItem *tabViewItem = (NSTabViewItem *)[sender representedObject];
	[tabView selectTabViewItem:tabViewItem];
}

- (void)closeTabClick:(id)sender
{
	NSTabViewItem *item = [sender representedObject];
    if(([_cells count] == 1) && (![self canCloseOnlyTab]))
        return;
    
    if ([[self delegate] respondsToSelector:@selector(tabView:shouldCloseTabViewItem:)]) {
        if (![[self delegate] tabView:tabView shouldCloseTabViewItem:item]) {
            return;
        }
    }
    
    if(item) {
        [tabView removeTabViewItem:item];
    }
}

- (void)tabClick:(id)sender
{
    [tabView selectTabViewItem:[sender representedObject]];
}

- (void)frameDidChange:(NSNotification *)notification
{
	[self _checkWindowFrame];
	[self updateTabBarAndUpdateTabs:NO];
}

- (void)viewDidMoveToWindow
{
	[self _checkWindowFrame];
}

- (void)viewWillStartLiveResize
{
    NSEnumerator *e = [_cells objectEnumerator];
    PSMTabBarCell *cell;
    while ( (cell = [e nextObject]) ) {
        [[cell indicator] stopAnimation:self];
    }
    [self setNeedsDisplay:YES];
}

-(void)viewDidEndLiveResize
{
    NSEnumerator *e = [_cells objectEnumerator];
    PSMTabBarCell *cell;
    while ( (cell = [e nextObject]) ) {
        [[cell indicator] startAnimation:self];
    }
	
	[self _checkWindowFrame];
    [self update];
}

- (void)resetCursorRects
{
	[super resetCursorRects];
	if ([self orientation] == PSMTabBarVerticalOrientation) {
		NSRect frame = [self frame];
		[self addCursorRect:NSMakeRect(frame.size.width - 2, 0, 2, frame.size.height) cursor:[NSCursor resizeLeftRightCursor]];
	}
}

- (void)windowDidMove:(NSNotification *)aNotification
{
    [self setNeedsDisplay:YES];
}

- (void)windowDidUpdate:(NSNotification *)notification
{
	// Determine whether a draw update in response to window state change might be required
	BOOL isMainWindow = [[self window] isMainWindow];
	BOOL attachedWindowIsMainWindow = [[[self window] attachedSheet] isMainWindow];
	BOOL isActiveApplication = [NSApp isActive];
	if (_lastWindowIsMainCheck != isMainWindow || _lastAttachedWindowIsMainCheck != attachedWindowIsMainWindow || _lastAppIsActiveCheck != isActiveApplication) {
		_lastWindowIsMainCheck = isMainWindow;
		_lastAttachedWindowIsMainCheck = attachedWindowIsMainWindow;
		_lastAppIsActiveCheck = isActiveApplication;

		// Allow the tab bar to redraw itself in result to window ordering/sheet/etc changes
		[self setNeedsDisplay:YES];
	}
}

#pragma mark -
#pragma mark Menu Validation

- (BOOL)validateMenuItem:(NSMenuItem *)sender
{
	[sender setState:([[sender representedObject] isEqualTo:[tabView selectedTabViewItem]]) ? NSOnState : NSOffState];
	
	return [[self delegate] respondsToSelector:@selector(tabView:validateOverflowMenuItem:forTabViewItem:)] ?
		[[self delegate] tabView:[self tabView] validateOverflowMenuItem:sender forTabViewItem:[sender representedObject]] : YES;
}

#pragma mark -
#pragma mark NSTabView Delegate

- (void)tabView:(NSTabView *)aTabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
    // here's a weird one - this message is sent before the "tabViewDidChangeNumberOfTabViewItems"
    // message, thus I can end up updating when there are no cells, if no tabs were (yet) present
	NSInteger tabIndex = [aTabView indexOfTabViewItem:tabViewItem];
	
    if ([_cells count] > 0 && tabIndex < (NSInteger)[_cells count]) {
		PSMTabBarCell *thisCell = [_cells objectAtIndex:tabIndex];
		if (_alwaysShowActiveTab && [thisCell isInOverflowMenu]) {
			
			//temporarily disable the delegate in order to move the tab to a different index
			id tempDelegate = [aTabView delegate];
			[aTabView setDelegate:nil];
			
			// move it all around first
			[aTabView removeTabViewItem:tabViewItem];
			[aTabView insertTabViewItem:tabViewItem atIndex:0];
			[_cells removeObjectAtIndex:tabIndex];
			[_cells insertObject:thisCell atIndex:0];
			[thisCell setIsInOverflowMenu:NO];	//very important else we get a fun recursive loop going
			[[_cells objectAtIndex:[_cells count] - 1] setIsInOverflowMenu:YES]; //these 2 lines are pretty uncool and this logic needs to be updated
			
			[aTabView setDelegate:tempDelegate];
			
            //reset the selection since removing it changed the selection
			[aTabView selectTabViewItem:tabViewItem];
            
			[self update];
		} else {
            [_controller setSelectedCell:thisCell];
            [self setNeedsDisplay:YES];
		}
    }
	
	if ([[self delegate] respondsToSelector:@selector(tabView:didSelectTabViewItem:)]) {
		[[self delegate] performSelector:@selector(tabView:didSelectTabViewItem:) withObject:aTabView withObject:tabViewItem];
	}
}

- (BOOL)tabView:(NSTabView *)aTabView shouldSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
	if ([[self delegate] respondsToSelector:@selector(tabView:shouldSelectTabViewItem:)]) {
		return [[self delegate] tabView:aTabView shouldSelectTabViewItem:tabViewItem];
	} else {
		return YES;
	}
}
- (void)tabView:(NSTabView *)aTabView willSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
	if ([[self delegate] respondsToSelector:@selector(tabView:willSelectTabViewItem:)]) {
		[[self delegate] performSelector:@selector(tabView:willSelectTabViewItem:) withObject:aTabView withObject:tabViewItem];
	}
}

- (void)tabViewDidChangeNumberOfTabViewItems:(NSTabView *)aTabView
{
    NSArray *tabItems = [tabView tabViewItems];
    // go through cells, remove any whose representedObjects are not in [tabView tabViewItems]
    NSEnumerator *e = [[_cells copy] objectEnumerator];
    PSMTabBarCell *cell;
    while ( (cell = [e nextObject]) ) {
		//remove the observer binding
        if ([cell representedObject] && ![tabItems containsObject:[cell representedObject]]) {
			// see issue #2609
			// -removeTabForCell: comes first to stop the observing that would be triggered in the delegate's call tree
			// below and finally caused a crash.
			[self removeTabForCell:cell];
			
			if ([[self delegate] respondsToSelector:@selector(tabView:didCloseTabViewItem:)]) {
				[[self delegate] tabView:aTabView didCloseTabViewItem:[cell representedObject]];
			}
        }
    }
    
    // go through tab view items, add cell for any not present
    NSMutableArray *cellItems = [self representedTabViewItems];
    NSEnumerator *ex = [tabItems objectEnumerator];
    NSTabViewItem *item;
    while ( (item = [ex nextObject]) ) {
        if (![cellItems containsObject:item]) {
            [self addTabViewItem:item];
        }
    }

    // pass along for other delegate responses
    if ([[self delegate] respondsToSelector:@selector(tabViewDidChangeNumberOfTabViewItems:)]) {
        [[self delegate] performSelector:@selector(tabViewDidChangeNumberOfTabViewItems:) withObject:aTabView];
    }
	
	// reset cursor tracking for the add tab button if one exists
	if ([self addTabButton]) [[self addTabButton] resetCursorRects];
}

#pragma mark -
#pragma mark Tooltips

- (NSString *)view:(NSView *)view stringForToolTip:(NSToolTipTag)tag point:(NSPoint)point userData:(void *)userData
{
	if ([[self delegate] respondsToSelector:@selector(tabView:toolTipForTabViewItem:)]) {
		return [[self delegate] tabView:[self tabView] toolTipForTabViewItem:[[self cellForPoint:point cellFrame:nil] representedObject]];
	}
	return nil;
}

#pragma mark -
#pragma mark Archiving

- (void)encodeWithCoder:(NSCoder *)aCoder 
{
    [super encodeWithCoder:aCoder];
    if ([aCoder allowsKeyedCoding]) {
        [aCoder encodeObject:_cells forKey:@"PSMcells"];
        [aCoder encodeObject:tabView forKey:@"PSMtabView"];
        [aCoder encodeObject:_overflowPopUpButton forKey:@"PSMoverflowPopUpButton"];
        [aCoder encodeObject:_addTabButton forKey:@"PSMaddTabButton"];
        [aCoder encodeObject:style forKey:@"PSMstyle"];
		[aCoder encodeInteger:_orientation forKey:@"PSMorientation"];
        [aCoder encodeBool:_canCloseOnlyTab forKey:@"PSMcanCloseOnlyTab"];
		[aCoder encodeBool:_disableTabClose forKey:@"PSMdisableTabClose"];
		[aCoder encodeBool:_allowsBackgroundTabClosing forKey:@"PSMallowsBackgroundTabClosing"];
		[aCoder encodeBool:_allowsResizing forKey:@"PSMallowsResizing"];
		[aCoder encodeBool:_selectsTabsOnMouseDown forKey:@"PSMselectsTabsOnMouseDown"];
        [aCoder encodeBool:_showAddTabButton forKey:@"PSMshowAddTabButton"];
        [aCoder encodeBool:_sizeCellsToFit forKey:@"PSMsizeCellsToFit"];
        [aCoder encodeInteger:_cellMinWidth forKey:@"PSMcellMinWidth"];
        [aCoder encodeInteger:_cellMaxWidth forKey:@"PSMcellMaxWidth"];
        [aCoder encodeInteger:_cellOptimumWidth forKey:@"PSMcellOptimumWidth"];
        [aCoder encodeObject:partnerView forKey:@"PSMpartnerView"];
        [aCoder encodeBool:_awakenedFromNib forKey:@"PSMawakenedFromNib"];
        [aCoder encodeObject:_lastMouseDownEvent forKey:@"PSMlastMouseDownEvent"];
        [aCoder encodeObject:delegate forKey:@"PSMdelegate"];
		[aCoder encodeBool:_useOverflowMenu forKey:@"PSMuseOverflowMenu"];
		[aCoder encodeBool:_alwaysShowActiveTab forKey:@"PSMalwaysShowActiveTab"];
    }
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder 
{
    self = [super initWithCoder:aDecoder];
    if (self) {

            // Initialization
        [self initAddedProperties];
        [self registerForDraggedTypes:@[@"PSMTabBarControlItemPBType"]];
    
        if ([aDecoder allowsKeyedCoding]) {
            _cells = [aDecoder decodeObjectForKey:@"PSMcells"];
            tabView = [aDecoder decodeObjectForKey:@"PSMtabView"];
            _overflowPopUpButton = [aDecoder decodeObjectForKey:@"PSMoverflowPopUpButton"];
            _addTabButton = [aDecoder decodeObjectForKey:@"PSMaddTabButton"];
            style = [aDecoder decodeObjectForKey:@"PSMstyle"];
			_orientation = (PSMTabBarOrientation)[aDecoder decodeIntegerForKey:@"PSMorientation"];
            _canCloseOnlyTab = [aDecoder decodeBoolForKey:@"PSMcanCloseOnlyTab"];
			_disableTabClose = [aDecoder decodeBoolForKey:@"PSMdisableTabClose"];
			_allowsBackgroundTabClosing = [aDecoder decodeBoolForKey:@"PSMallowsBackgroundTabClosing"];
			_allowsResizing = [aDecoder decodeBoolForKey:@"PSMallowsResizing"];
			_selectsTabsOnMouseDown = [aDecoder decodeBoolForKey:@"PSMselectsTabsOnMouseDown"];
            _showAddTabButton = [aDecoder decodeBoolForKey:@"PSMshowAddTabButton"];
            _sizeCellsToFit = [aDecoder decodeBoolForKey:@"PSMsizeCellsToFit"];
            _cellMinWidth = [aDecoder decodeIntegerForKey:@"PSMcellMinWidth"];
            _cellMaxWidth = [aDecoder decodeIntegerForKey:@"PSMcellMaxWidth"];
            _cellOptimumWidth = [aDecoder decodeIntegerForKey:@"PSMcellOptimumWidth"];
            partnerView = [aDecoder decodeObjectForKey:@"PSMpartnerView"];
            _awakenedFromNib = [aDecoder decodeBoolForKey:@"PSMawakenedFromNib"];
            _lastMouseDownEvent = [aDecoder decodeObjectForKey:@"PSMlastMouseDownEvent"];
			_useOverflowMenu = [aDecoder decodeBoolForKey:@"PSMuseOverflowMenu"];
			_alwaysShowActiveTab = [aDecoder decodeBoolForKey:@"PSMalwaysShowActiveTab"];
            delegate = [aDecoder decodeObjectForKey:@"PSMdelegate"];
        }
        
            // resize
        [self setPostsFrameChangedNotifications:YES];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(frameDidChange:) name:NSViewFrameDidChangeNotification object:self];
    }
    
    [self setTarget:self];    
    return self;
}

#pragma mark -
#pragma mark IB Palette

- (NSSize)minimumFrameSizeFromKnobPosition:(NSInteger)position
{
    return NSMakeSize(100.0f, 22.0f);
}

- (NSSize)maximumFrameSizeFromKnobPosition:(NSInteger)knobPosition
{
    return NSMakeSize(10000.0f, 22.0f);
}

- (void)placeView:(NSRect)newFrame
{
    // this is called any time the view is resized in IB
    [self setFrame:newFrame];
    [self update];
}

#pragma mark -
#pragma mark Convenience

- (void)bindPropertiesForCell:(PSMTabBarCell *)cell andTabViewItem:(NSTabViewItem *)item
{
    [self _bindPropertiesForCell:cell andTabViewItem:item];
    
    // watch for changes in the identifier
    [item addObserver:self forKeyPath:@"identifier" options:0 context:nil];
}

- (void)_bindPropertiesForCell:(PSMTabBarCell *)cell andTabViewItem:(NSTabViewItem *)item {

    SPDatabaseDocument *databaseDocument = [item databaseDocument];
    // bind the indicator to the represented object's status (if it exists)
    [[cell indicator] setHidden:YES];
    if (databaseDocument != nil) {
		if ([databaseDocument respondsToSelector:@selector(isProcessing)]) {
			NSMutableDictionary *bindingOptions = [NSMutableDictionary dictionary];
			[bindingOptions setObject:NSNegateBooleanTransformerName forKey:@"NSValueTransformerName"];
			[[cell indicator] bind:@"animate" toObject:databaseDocument withKeyPath:@"isProcessing" options:nil];
			[[cell indicator] bind:@"hidden" toObject:databaseDocument withKeyPath:@"isProcessing" options:bindingOptions];
            [databaseDocument addObserver:cell forKeyPath:@"isProcessing" options:0 context:nil];
        }
    }
    
    // bind for the existence of an icon
    [cell setHasIcon:NO];
    if (databaseDocument != nil) {
		if ([databaseDocument respondsToSelector:@selector(icon)]) {
			NSMutableDictionary *bindingOptions = [NSMutableDictionary dictionary];
			[bindingOptions setObject:NSIsNotNilTransformerName forKey:@"NSValueTransformerName"];
			[cell bind:@"hasIcon" toObject:databaseDocument withKeyPath:@"icon" options:bindingOptions];
			[databaseDocument addObserver:cell forKeyPath:@"icon" options:0 context:nil];
        }
    }
    
    // bind for the existence of a counter
    [cell setCount:0];
    if (databaseDocument != nil) {
		if ([databaseDocument respondsToSelector:@selector(count)]) {
			[cell bind:@"count" toObject:databaseDocument withKeyPath:@"objectCount" options:nil];
			[databaseDocument addObserver:cell forKeyPath:@"objectCount" options:0 context:nil];
		}
    }
	
    // bind for the color of a counter
    [cell setCountColor:nil];
    if (databaseDocument != nil) {
		if ([databaseDocument respondsToSelector:@selector(countColor)]) {
			[cell bind:@"countColor" toObject:databaseDocument withKeyPath:@"countColor" options:nil];
			[databaseDocument addObserver:cell forKeyPath:@"countColor" options:0 context:nil];
		}
    }

	// bind for a large image
	[cell setHasLargeImage:NO];
    if (databaseDocument != nil) {
		if ([databaseDocument respondsToSelector:@selector(largeImage)]) {
			NSMutableDictionary *bindingOptions = [NSMutableDictionary dictionary];
			[bindingOptions setObject:NSIsNotNilTransformerName forKey:@"NSValueTransformerName"];
			[cell bind:@"hasLargeImage" toObject:databaseDocument withKeyPath:@"largeImage" options:bindingOptions];
			[databaseDocument addObserver:cell forKeyPath:@"largeImage" options:0 context:nil];
		}
    }
	
    [cell setIsEdited:NO];
    if (databaseDocument != nil) {
		if ([databaseDocument respondsToSelector:@selector(isEdited)]) {
			[cell bind:@"isEdited" toObject:databaseDocument withKeyPath:@"isEdited" options:nil];
			[databaseDocument addObserver:cell forKeyPath:@"isEdited" options:0 context:nil];
		}
    }
    
    // bind my string value to the label on the represented tab
    [cell bind:@"title" toObject:item withKeyPath:@"label" options:nil];
	[cell bind:@"backgroundColor" toObject:item withKeyPath:@"color" options:nil];
}

- (NSMutableArray *)representedTabViewItems
{
    NSMutableArray *temp = [NSMutableArray arrayWithCapacity:[_cells count]];
    NSEnumerator *e = [_cells objectEnumerator];
    PSMTabBarCell *cell;
    while ( (cell = [e nextObject])) {
        if ([cell representedObject]) {
			[temp addObject:[cell representedObject]];
		}
    }
    return temp;
}

- (id)cellForPoint:(NSPoint)point cellFrame:(NSRectPointer)outFrame
{
    if ([self orientation] == PSMTabBarHorizontalOrientation && !NSPointInRect(point, [self genericCellRect])) {
        return nil;
    }
    
    NSInteger i, cnt = [_cells count];
    for (i = 0; i < cnt; i++) {
        PSMTabBarCell *cell = [_cells objectAtIndex:i];
        
		if (NSPointInRect(point, [cell frame])) {
            if (outFrame) {
                *outFrame = [cell frame];
            }
            return cell;
        }
    }
    return nil;
}

- (PSMTabBarCell *)lastVisibleTab {
    NSInteger i, cellCount = [_cells count];
    for (i = 0; i < cellCount; i++) {
        if ([[_cells objectAtIndex:i] isInOverflowMenu]) {
            return [_cells objectAtIndex:(i - 1)];
        }
    }
    return [_cells objectAtIndex:(cellCount - 1)];
}

- (NSUInteger)numberOfVisibleTabs {
    NSUInteger i, cellCount = 0;
	PSMTabBarCell *nextCell;
	
    for (i = 0; i < [_cells count]; i++) {
		nextCell = [_cells objectAtIndex:i];
		
		if ([nextCell isInOverflowMenu]) {
            break;
        }
		
		if (![nextCell isPlaceholder]) {
			cellCount++;
		}
    }
	
    return cellCount;
}

@end
