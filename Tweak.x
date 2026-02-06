%config(generator=internal);

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <os/log.h>
#import <PhotosUI/PhotosUI.h>

#define log(fmt, ...) os_log(OS_LOG_DEFAULT, "%{public}s", [[NSString stringWithFormat:(fmt), ##__VA_ARGS__] UTF8String]); 

@interface IGCoreTextView : UIView
@property (nonatomic, copy) NSString *text;
@end

@interface IGUsernameLabel : UIView
@property (retain, nonatomic) IGCoreTextView* nameLabel;
@end

@interface IGDirectInboxThreadCell : UIView
- (IGUsernameLabel *)usernameLabel;
@end

@interface IGDirectInboxViewController : UIViewController

@property (nonatomic, retain) NSString* dmbg_targetUsername;
@property (nonatomic, retain) IGDirectInboxThreadCell* dmbg_targetCell;
- (id) collectionView:(id)arg1 contextMenuConfigurationForItemAtIndexPath:(id)arg2 point:(struct CGPoint)arg3;

@end

void image_SaveToNSUserDefaults(NSString* key, UIImage* image) {
    NSData *imageData = UIImagePNGRepresentation(image);
    [[NSUserDefaults standardUserDefaults] setObject:imageData forKey:key];
    
    while (![[NSUserDefaults standardUserDefaults] synchronize]) {
        // Keep trying to synchronize until successful
    }
}

UIImage* image_LoadFromNSUserDefaults(NSString* key) {
    NSData *imageData = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (imageData) {
        return [UIImage imageWithData:imageData];
    }
    return nil;
}

NSString* dmbg_cellGetUsername(IGDirectInboxThreadCell* cell) {
    IGUsernameLabel *label = [cell usernameLabel];
    IGCoreTextView *nameLabel = label.nameLabel;
    return nameLabel.text;
}

NSMutableSet* dmbg_targetUsernames;

NSMutableDictionary<NSString*, UIImage*>* dmbg_usernameToImageMap;

IGDirectInboxViewController* dmbg_viewController = nil;

%hook IGDirectInboxThreadCell

- (void)prepareForReuse {
   // log(@"[igcdmbg] Preparing cell for reuse for user: %@", dmbg_cellGetUsername(self));
   
    %orig;

    self.layer.contents = nil;
    self.layer.masksToBounds = NO;
    self.layer.contentsGravity = kCAGravityResize;
}

-(void) layoutSubviews {
    CALayer* layer = (self).layer;
                    
    NSString* username = dmbg_cellGetUsername(self);

    //log(@"[igcdmbg] hook called for %@", username);

    if ([dmbg_targetUsernames containsObject:username]) {
        layer.contents = (id)dmbg_usernameToImageMap[username].CGImage;
        layer.contentsGravity = kCAGravityResizeAspectFill;
        layer.masksToBounds = YES;
      //  log(@"[igcdmbg] Changing contents for %@", username);
        %orig;
        } 
    else {
        %orig;
    }                                
}

%end

%hook IGDirectInboxViewController

%property (nonatomic, retain) NSString* dmbg_targetUsername;
%property (nonatomic, retain) IGDirectInboxThreadCell* dmbg_targetCell;

%new 
- (void) picker:(PHPickerViewController *) picker 
didFinishPicking:(NSArray<PHPickerResult *> *) results{
    
    [picker dismissViewControllerAnimated:YES completion:nil];

    if (results.count == 0) {
       // log(@"[igcdmbg] No image selected");
        return;
    }

    PHPickerResult *result = results.firstObject;

    if (![result.itemProvider canLoadObjectOfClass:[UIImage class]]) {
        //log(@"[igcdmbg] Selected item is not an image");
        return;
    }

    [result.itemProvider loadObjectOfClass:[UIImage class] completionHandler:^(UIImage *image, NSError *error) {
        if (error) {
          //  log(@"[igcdmbg] Error loading image: %@", error);
            return;
        }

        if (image) {
           // log(@"[igcdmbg] Image selected successfully");
            dmbg_usernameToImageMap[dmbg_viewController.dmbg_targetUsername] = image;
            NSString* key = [NSString stringWithFormat:@"dmbg_%@", dmbg_viewController.dmbg_targetUsername];
            image_SaveToNSUserDefaults(key, dmbg_usernameToImageMap[dmbg_viewController.dmbg_targetUsername]);
            dispatch_async(dispatch_get_main_queue(), ^{
                [dmbg_viewController.dmbg_targetCell layoutSubviews];
            });
        }
    }];
}

-(void)viewDidLoad {

    if (self) {
        dmbg_viewController = self;
    }

    %orig;
    
}

- (id)collectionView:(id)collectionView
contextMenuConfigurationForItemAtIndexPath:(id)indexPath
               point:(CGPoint)point
{
    UIContextMenuConfiguration *origConfig = %orig;

    if (!origConfig) {
        return origConfig;
    }

    id identifier = [origConfig valueForKey:@"identifier"];
    id previewProvider = [origConfig valueForKey:@"previewProvider"];
    UIContextMenuActionProvider actionProvider = [origConfig valueForKey:@"actionProvider"];

    UIContextMenuConfiguration *newConfig =
    [UIContextMenuConfiguration
     configurationWithIdentifier:identifier
     previewProvider:previewProvider
     actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggestedActions) {

        UIMenu* origMenu = actionProvider(suggestedActions);

        NSMutableArray *newChildren = [origMenu.children mutableCopy];

        int trust = 0;
        BOOL alreadyAdded = NO;

        for (UIMenuElement *element in origMenu.children) {
            if ([element isKindOfClass:[UIAction class]] && [element.title isEqualToString:@"Add background"]) {
                 alreadyAdded = YES;
                 break;
            }
        }

        for (UIMenuElement *element in origMenu.children) {
            if (alreadyAdded || trust >= 3) {
                break;
            }

            NSString *title = element.title;

                if ([title isEqualToString:@"Mark as unread"]) {
                    trust = 3;
                }
                else if ([title isEqualToString:@"Pin"] ||
                         [title isEqualToString:@"Mute"] ||
                         [title isEqualToString:@"Delete"]) {
                    trust++;
                }
            }

        if (trust >= 3) {
            UIAction *newAction =
            [UIAction actionWithTitle:@"Add background"
                                image:[UIImage systemImageNamed:@"photo"]
                           identifier:nil
                              handler:^(__kindof UIAction *action) {

    //HANDLER START

                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{

               // log(@"[igcdmbg] 'Add background' action selected for indexPath: %@", indexPath);

                UICollectionView* cv = [self valueForKey:@"_collectionView"];
                IGDirectInboxThreadCell* cell = [cv cellForItemAtIndexPath:indexPath];
                self.dmbg_targetCell = cell;

                NSString* username = dmbg_cellGetUsername(cell);
                self.dmbg_targetUsername = username;
                [dmbg_targetUsernames addObject:username];

                PHPickerConfiguration *config = [[PHPickerConfiguration alloc] init];
        
                // Limit selection (0 = unlimited)
                config.selectionLimit = 1;
                // Filter to images only (or videos, or both)
                config.filter = [PHPickerFilter imagesFilter];

                PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
        
                picker.delegate = self;
        
                [self presentViewController:picker animated:YES completion:nil]; 

              //  log(@"[igcdmbg] 'Add background' action selected for user: %@", username);

              //  log(@"[igcdmbg] action finished");
                 
                });
                

            }];

            [newChildren addObject:newAction];
        }

        // Return a new menu
        return [UIMenu menuWithTitle:origMenu.title
                                image:origMenu.image
                           identifier:origMenu.identifier
                              options:origMenu.options
                             children:newChildren];
    }];

  //  log(@"[igcdmbg] returned context menu config for %@", indexPath);

    return newConfig;
}


%end

%ctor {
    dmbg_targetUsernames = [NSMutableSet set];
    dmbg_usernameToImageMap = [NSMutableDictionary dictionary];

    //Persistance: Load saved images from NSUserDefaults
    for (NSString *key in [[NSUserDefaults standardUserDefaults] dictionaryRepresentation]) {
        if ([key hasPrefix:@"dmbg_"]) {
            UIImage* image = image_LoadFromNSUserDefaults(key);
            NSString* username = [key substringFromIndex:5];
            if (image) {
                dmbg_usernameToImageMap[username] = image;
                [dmbg_targetUsernames addObject:username];
              //  log(@"[igcdmbg] Loaded background for user: %@", username);
            }
        }
    }
            

}