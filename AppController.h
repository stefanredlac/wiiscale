#import <Cocoa/Cocoa.h>

#import "PrefsController.h"
#import "WiiRemote.h"
#import "WiiRemoteDiscovery.h"
#import "GData/GDataHealth.h"

@interface AppController : NSWindowController<WiiRemoteDelegate, WiiRemoteDiscoveryDelegate> {
	IBOutlet NSProgressIndicator* spinner;
	IBOutlet NSProgressIndicator* ghspinner;
	IBOutlet NSTextField* weight;
	IBOutlet NSTextField* status;
	IBOutlet NSTextField* bbstatus;
	IBOutlet NSProgressIndicator* weightProgress;
	IBOutlet NSPopUpButton* profilesPopUp;
	IBOutlet NSMenuItem* fileConnect;
	IBOutlet NSMenuItem* fileTare;
	IBOutlet NSWindow* prefs;
	IBOutlet PrefsController *prefsController;

	WiiRemoteDiscovery* discovery;
	WiiRemote* wii;
	
	NSSound *mailSent;
	
	GDataServiceGoogleHealth* service;
	GDataFeedHealthProfile* profiles;
	
	float tare;
	float avgWeight;
	float sentWeight;
	float lastWeight;
	float weightSamples[100];
	int weightSampleIndex;
	BOOL sent;
}

- (IBAction)doDiscovery:(id)sender;
- (IBAction)doTare:(id)sender;

- (void)loginGoogleHealth:(id)sender;
- (void)sendToGoogleHealth:(id)sender;

- (IBAction)showPrefs:(id)sender;
- (IBAction)profileChanged:(id)sender;

@end
