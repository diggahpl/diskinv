/* MainWindowController */

#import <Cocoa/Cocoa.h>
#import "FileSystemDoc.h"
#import <TreeMapView/TreeMapView.h>
#import "OAToolbarWindowControllerEx.h"

// NSDrawer was deprecated in 10.13 with the suggestion to "consider using NSSplitViewController",
// but it still works on macOS 26 and migrating is a UI redesign. Suppress the deprecation warnings
// at the boundary so callers of this header don't get noise either.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@interface MainWindowController : OAToolbarWindowControllerEx
{
    IBOutlet NSDrawer *_kindsDrawer;
    IBOutlet NSDrawer *_selectionListDrawer;
	IBOutlet NSSplitView *_splitter;
	IBOutlet NSOutlineView *_filesOutlineView;
	IBOutlet TreeMapView *_treeMapView;
	IBOutlet NSMenu *_openWithSubMenu;
}

+ (FileSystemDoc*) documentForView: (NSView*) view;

+ (void) poofEffectInView: (NSView*)view inRect: (NSRect) rect; //rect in view coords

- (NSDrawer*) kindStatisticsDrawer;
- (NSDrawer*) selectionListDrawer;

- (IBAction) openFile:(id)sender;
- (IBAction) toggleFileKindsDrawer:(id)sender;
- (IBAction) toggleSelectionListDrawer:(id)sender;
- (IBAction) zoomIn:(id)sender;
- (IBAction) zoomOut:(id)sender;
- (IBAction) zoomOutTo:(id)sender;
- (IBAction) showInFinder:(id)sender;
- (IBAction) refresh:(id)sender;
- (IBAction) refreshAll:(id)sender;
- (IBAction) moveToTrash:(id)sender;
- (IBAction) showPackageContents:(id)sender;
- (IBAction) showFreeSpace:(id)sender;
- (IBAction) showOtherSpace:(id)sender;
- (IBAction) selectParentItem:(id)sender;
- (IBAction) changeSplitting:(id)sender;
- (IBAction) showInformationPanel:(id)sender;
- (IBAction) showPhysicalSizes:(id) sender;
- (IBAction) ignoreCreatorCode:(id) sender;

- (IBAction) performRenderBenchmark:(id)sender;
- (IBAction) performLayoutBenchmark:(id)sender;
@end

#pragma clang diagnostic pop
