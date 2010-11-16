#import "AppController.h"

@implementation AppController

#pragma mark Preferences

- (IBAction)showPrefs:(id)sender
{
	[NSApp beginSheet:prefs modalForWindow:self.window modalDelegate:self didEndSelector:@selector(didEndSheet:returnCode:contextInfo:) contextInfo:nil];	
}

- (void)didEndSheet:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	[sheet orderOut:self];
	
	NSString *username = [[NSUserDefaults standardUserDefaults] stringForKey:@"username"];
	NSString *password = [[NSUserDefaults standardUserDefaults] stringForKey:@"password"];
	
	if(username.length && password.length)
		[self performSelector:@selector(loginGoogleHealth:) withObject:self afterDelay:0.0f];	
}

#pragma mark Window

- (id)init
{
    self = [super init];
    if (self) {
		
		weightSampleIndex = 0;
				
		service = [[GDataServiceGoogleHealth alloc] init];
		[service setUserAgent:@"FordParsons-WiiScaleMac-1.0"];
		[service setShouldCacheDatedData:YES];
		[service setServiceShouldFollowNextLinks:YES];
		
		NSString *username = [[NSUserDefaults standardUserDefaults] stringForKey:@"username"];
		NSString *password = [[NSUserDefaults standardUserDefaults] stringForKey:@"password"];
		
		if(username.length && password.length)
			[self performSelector:@selector(loginGoogleHealth:) withObject:self afterDelay:0.0f];
		else
			[self performSelector:@selector(showPrefs:) withObject:self afterDelay:0.0f];
		
		[self performSelectorInBackground:@selector(showMessage) withObject:nil];
		
		if(!discovery) {
			[self performSelector:@selector(doDiscovery:) withObject:self afterDelay:0.0f];
		}
		
		mailSent = [[NSSound alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"mail-sent" ofType:@"aiff"] byReference:NO];
		
    }
    return self;
}

- (void)dealloc
{
	[super dealloc];
	[mailSent release];
	[service release];
	[profiles release];
}

- (void)awakeFromNib {

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(expansionPortChanged:)
												 name:@"WiiRemoteExpansionPortChangedNotification"
											   object:nil];
}

- (void)showMessage
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSDictionary *d = [NSDictionary dictionaryWithContentsOfURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://snosrap.com/wiiscale/message%@.plist", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"]]]];
	if(!!d)
		[self performSelectorOnMainThread:@selector(showMessage:) withObject:d waitUntilDone:NO];

	[pool release];
}

- (void)showMessage:(NSDictionary *)d
{
	[[NSAlert alertWithMessageText:[d objectForKey:@"Title"] defaultButton:@"Okay" alternateButton:nil otherButton:nil informativeTextWithFormat:[d objectForKey:@"Message"]] runModal];
}

#pragma mark NSApplication

- (void)applicationWillTerminate:(NSNotification *)notification
{
	[wii closeConnection];
}

#pragma mark Google

- (void)loginGoogleHealth:(id)sender {
	
	[ghspinner startAnimation:self];
	
	// username/password may change
	NSString *username = [[NSUserDefaults standardUserDefaults] stringForKey:@"username"];
	NSString *password = [[NSUserDefaults standardUserDefaults] stringForKey:@"password"];
	
	if(username.length && password.length) {
		
		[service setUserCredentialsWithUsername:username
									   password:password];
		
		[service fetchFeedWithURL:[[GDataServiceGoogleHealth class] profileListFeedURL]
						 delegate:self
				didFinishSelector:@selector(profileListFeedTicket:finishedWithFeed:error:)];
	}
}

- (void)profileListFeedTicket:(GDataServiceTicket *)ticket
             finishedWithFeed:(GDataFeedBase *)feed
                        error:(NSError *)error {
		
	if(!error) {
		[profiles release];
		profiles = [feed retain];

		[profilesPopUp removeAllItems];
		for(GDataEntryHealthProfile* p in [profiles entries])
			[profilesPopUp addItemWithTitle:[[p title] stringValue]];
		
		NSString *profileName = [[NSUserDefaults standardUserDefaults] stringForKey:@"profileName"];
		if(profileName.length && !![profilesPopUp itemWithTitle:profileName])
			[profilesPopUp selectItemWithTitle:profileName];
		
	} else {
		[[NSAlert alertWithError:error] runModal]; // TODO: nicer errors?
	}

	[ghspinner stopAnimation:self];
}

- (IBAction)profileChanged:(id)sender {
	[[NSUserDefaults standardUserDefaults] setValue:[(NSPopUpButton *)sender titleOfSelectedItem] forKey:@"profileName"];
	[[NSUserDefaults standardUserDefaults] synchronize];	
}

- (void)sendToGoogleHealth:(id)sender {
	
	if(!service)
		[self loginGoogleHealth:self];
	
	sentWeight = avgWeight;
	
	GDataEntryHealthProfile *entry = [[[GDataEntryHealthProfile alloc] init] autorelease];
	
	NSString *format = [NSString stringWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"weight" ofType:@"xml"] encoding:NSUTF8StringEncoding error:nil];
	NSString *ccr = [NSString stringWithFormat:format,
					 [[GDataDateTime dateTimeWithDate:[NSDate date] timeZone:[NSTimeZone localTimeZone]] RFC3339String],
					 sentWeight];	 

	[entry setContinuityOfCareRecord:[[[GDataContinuityOfCareRecord alloc] initWithXMLElement:
									   [[[NSXMLElement alloc] initWithXMLString:ccr
																		  error:nil] autorelease] parent:nil] autorelease]];
	
	[entry setTitleWithString:@"Weight Update from WiiScale"];
	
	[service fetchEntryByInsertingEntry:entry
							 forFeedURL:[GDataServiceGoogleHealth registerFeedURLForProfileID:[[(GDataEntryHealthProfile *)[[profiles entries] objectAtIndex:[profilesPopUp indexOfSelectedItem]] content] stringValue]]
							   delegate:self
					  didFinishSelector:@selector(fetchEntryByInsertingEntry:finishedWithEntry:error:)];	
}

- (void)fetchEntryByInsertingEntry:(GDataServiceTicket *)ticket
				 finishedWithEntry:(GDataFeedBase *)feed
							 error:(NSError *)error {
	
	if(!!error)
	{
		[[NSAlert alertWithError:error] runModal]; // TODO: nicer error?
		
	}
	else
	{
		[mailSent play];
	}
}

#pragma mark Wii Balance Board

- (IBAction)doDiscovery:(id)sender {
	
	if(!discovery) {
		discovery = [[WiiRemoteDiscovery alloc] init];
		[discovery setDelegate:self];
		[discovery start];
		
		[spinner startAnimation:self];
		[bbstatus setStringValue:@"Searching..."];
		[fileConnect setTitle:@"Stop Searching for Balance Board"];
		[status setStringValue:@"Press the red 'sync' button..."];
	} else {
		[discovery stop];
		[discovery release];
		discovery = nil;
		
		if(wii) {
			[wii closeConnection];
			[wii release];
			wii = nil;
		}
		
		[spinner stopAnimation:self];
		[bbstatus setStringValue:@"Disconnected"];
		[fileConnect setTitle:@"Connect to Balance Board"];
		[status setStringValue:@""];
	}
}

- (IBAction)doTare:(id)sender {
	tare = 0.0 - lastWeight;
}

#pragma mark Magic?

- (void)expansionPortChanged:(NSNotification *)nc{
	
	NSLog(@"expansionPortChanged");

	WiiRemote* tmpWii = (WiiRemote*)[nc object];
	
	// Check that the Wiimote reporting is the one we're connected to.
	if (![[tmpWii address] isEqualToString:[wii address]]){
		return;
	}
	
	if ([wii isExpansionPortAttached]){
		[wii setExpansionPortEnabled:YES];
	}	
}

#pragma mark WiiRemoteDelegate methods

- (void) buttonChanged:(WiiButtonType) type isPressed:(BOOL) isPressed
{
	NSLog(@"buttonChanged: %i, %i", type, isPressed);
	
	[self doTare:self];
}

- (void) wiiRemoteDisconnected:(IOBluetoothDevice*) device
{
	NSLog(@"wiiRemoteDisconnected");
	
	[spinner stopAnimation:self];
	[bbstatus setStringValue:@"Disconnected"];
	
	[device closeConnection];
}

#pragma mark WiiRemoteDelegate methods (optional)

- (void) analogButtonChanged:(WiiButtonType) type amount:(unsigned short) press {
	NSLog(@"analogButtonChanged: %i, %i", type, press);
}

- (void) accelerationChanged:(WiiAccelerationSensorType) type accX:(unsigned short) accX accY:(unsigned short) accY accZ:(unsigned short) accZ {
	NSLog(@"accelerationChanged: %i, %i, %i", accX, accY, accZ);
}

- (void) batteryLevelChanged:(double) level {
	NSLog(@"batteryLevelChanged: %f", level);
}

- (void) gotMiiData: (Mii*) mii_data_buf at: (int) slot {
	NSLog(@"gotMiiData");
}

- (void) irPointMovedX:(float) px Y:(float) py {
	NSLog(@"irPointMovedX");
}

- (void) joyStickChanged:(WiiJoyStickType) type tiltX:(unsigned short) tiltX tiltY:(unsigned short) tiltY {
	NSLog(@"joyStickChanged");
}

// raw values from the Balance Beam
/*- (void) balanceBeamChangedTopRight:(int)topRight
                        bottomRight:(int)bottomRight
                            topLeft:(int)topLeft
                         bottomLeft:(int)bottomLeft {
	//NSLog(@"balanceBeamChangedTopRight: %i, %i, %i, %i", topRight, bottomRight, topLeft, bottomLeft);
}*/

// cooked values from the Balance Beam
- (void) balanceBeamKilogramsChangedTopRight:(float)topRight
                                 bottomRight:(float)bottomRight
                                     topLeft:(float)topLeft
                                  bottomLeft:(float)bottomLeft {
	//NSLog(@"balanceBeamKilogramsChangedTopRight: %f, %f, %f, %f", topRight, bottomRight, topLeft, bottomLeft);
	
	lastWeight = topRight + bottomRight + topLeft + bottomLeft;
	
	if(!tare) {
		[self doTare:self];
	}
	
	float trueWeight = lastWeight + tare;
	[weightProgress setDoubleValue:trueWeight];
	
	if(trueWeight > 10.0) {
		weightSamples[weightSampleIndex] = trueWeight;
		weightSampleIndex = (weightSampleIndex + 1) % 100;
		
		float sum = 0;
		float sum_sqrs = 0;
		
		for (int i = 0; i < 100; i++)
		{
			sum += weightSamples[i];
			sum_sqrs += weightSamples[i] * weightSamples[i];
		}
		
		avgWeight = sum / 100.0;
		float var = sum_sqrs / 100.0 - (avgWeight * avgWeight);
		float std_dev = sqrt(var);
		
		//NSLog(@"%4.1f kg (%f)", avgWeight, std_dev);
		
		if(!sent)
			[status setStringValue:@"Please hold still..."];
		else
			[status setStringValue:[NSString stringWithFormat:@"Sent weight of %4.1fkg.  Thanks!", sentWeight]];

		
		if(std_dev < 0.1 && !sent)
		{
			sent = YES;
			[self sendToGoogleHealth:self];
		}
		
	} else {
		sent = NO;
		[status setStringValue:@"Tap the button to tare, then step on..."];
	}

	//[weight setStringValue:[NSString stringWithFormat:@"%4.1f kg", avgWeight]];
	//[weight setStringValue:[NSString stringWithFormat:@"%4.1f kg\t(%4.1f lbs)", trueWeight, (trueWeight) * 2.20462262]];
	[weight setStringValue:[NSString stringWithFormat:@"%4.1fkg  %4.1flbs", MAX(0.0, trueWeight), MAX(0.0, (trueWeight) * 2.20462262)]];
		
	//[weight setStringValue:[NSString stringWithFormat:@"%4.1fkg\t%4.1flbs", avgWeight, (avgWeight) * 2.20462262]];
}

- (void) rawIRData: (IRData[4]) irData {
	NSLog(@"rawIRData");
}

- (void) wiimoteWillSendData; {
	//NSLog(@"wiimoteWillSendData");
}

- (void) wiimoteDidSendData {
	//NSLog(@"wiimoteDidSendData");
}

#pragma mark WiiRemoteDiscoveryDelegate methods

- (void) WiiRemoteDiscovered:(WiiRemote*)wiimote {
	NSLog(@"WiiRemoteDiscovered");

	//[discovery stop];	
	
	[wii release];
	wii = [wiimote retain];
	[wii setDelegate:self];
	//[wii setExpansionPortEnabled:YES];
	//[wii setLEDEnabled1:YES enabled2:NO enabled3:NO enabled4:YES];
	//[wii setMotionSensorEnabled:YES];	
	[spinner stopAnimation:self];
	[bbstatus setStringValue:@"Connected"];
	//[wii setLEDEnabled1:YES enabled2:YES enabled3:YES enabled4:YES];
	
	[status setStringValue:@"Tap the button to tare, then step on..."];
}

- (void) WiiRemoteDiscoveryError:(int)code {
	
	NSLog(@"Error: %u", code);
		
	// Keep trying...
	[spinner stopAnimation:self];
	[discovery stop];
	sleep(1);
	[discovery start];
	[spinner startAnimation:self];
}

- (void) willStartWiimoteConnections {
	NSLog(@"willStartWiimoteConnections");
}
@end
