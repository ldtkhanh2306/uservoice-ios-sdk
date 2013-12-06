//
//  UVContactViewController.m
//  UserVoice
//
//  Created by Austin Taylor on 10/18/13.
//  Copyright (c) 2013 UserVoice Inc. All rights reserved.
//

#import "UVContactViewController.h"
#import "UVInstantAnswersViewController.h"
#import "UVDetailsFormViewController.h"
#import "UVSuccessViewController.h"
#import "UVTextView.h"
#import "UVSession.h"
#import "UVClientConfig.h"
#import "UVConfig.h"
#import "UVTicket.h"
#import "UVCustomField.h"
#import "UVBabayaga.h"

@implementation UVContactViewController {
    BOOL _proceed;
    BOOL _sending;
    NSLayoutConstraint *_keyboardConstraint;
    UVDetailsFormViewController *_detailsController;
}

- (void)loadView {
    UIView *view = [UIView new];
    view.backgroundColor = [UIColor whiteColor];
    view.frame = [self contentFrame];

    [self registerForKeyboardNotifications];
    _instantAnswerManager = [UVInstantAnswerManager new];
    _instantAnswerManager.delegate = self;
    _instantAnswerManager.articleHelpfulPrompt = NSLocalizedStringFromTable(@"Do you still want to contact us?", @"UserVoice", nil);
    _instantAnswerManager.articleReturnMessage = NSLocalizedStringFromTable(@"Yes, go to my message", @"UserVoice", nil);

    self.navigationItem.title = NSLocalizedStringFromTable(@"Send us a message", @"UserVoice", nil);
    self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStylePlain target:nil action:nil];

    _textView = [UVTextView new];
    _textView.placeholder = NSLocalizedStringFromTable(@"Give feedback or ask for help...", @"UserVoice", nil);
    _textView.delegate = self;

    NSArray *constraints = @[
        @"|-4-[_textView]-4-|", @"V:|[_textView]"
    ];
    [self configureView:view
               subviews:NSDictionaryOfVariableBindings(_textView)
            constraints:constraints];
    _keyboardConstraint = [NSLayoutConstraint constraintWithItem:_textView
                                                       attribute:NSLayoutAttributeBottom
                                                       relatedBy:NSLayoutRelationEqual
                                                          toItem:view
                                                       attribute:NSLayoutAttributeBottom
                                                      multiplier:1.0
                                                        constant:-_kbHeight];
    [view addConstraint:_keyboardConstraint];


    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedStringFromTable(@"Cancel", @"UserVoice", nil)
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(dismiss)];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedStringFromTable(@"Next", @"UserVoice", nil)
                                                                              style:UIBarButtonItemStyleDone
                                                                             target:self
                                                                             action:@selector(next)];
    [self loadDraft];
    self.navigationItem.rightBarButtonItem.enabled = (_textView.text.length > 0);
    self.view = view;
}

- (void)keyboardDidShow:(NSNotification *)note {
    _keyboardConstraint.constant = -_kbHeight;
    [self.view layoutIfNeeded];
}

- (void)keyboardDidHide:(NSNotification *)note {
    _keyboardConstraint.constant = 0;
    [self.view layoutIfNeeded];
}

- (void)viewWillAppear:(BOOL)animated {
    [_textView becomeFirstResponder];
    [super viewWillAppear:animated];
}

- (void)textViewDidChange:(UVTextView *)theTextEditor {
    self.navigationItem.rightBarButtonItem.enabled = (_textView.text.length > 0);
    _instantAnswerManager.searchText = theTextEditor.text;
}

- (void)didUpdateInstantAnswers {
    if (_proceed) {
        _proceed = NO;
        [self hideActivityIndicator];
        [_instantAnswerManager pushInstantAnswersViewForParent:self articlesFirst:YES];
    }
}

- (void)next {
    _proceed = YES;
    [self showActivityIndicator];
    [_instantAnswerManager search];
    if (!_instantAnswerManager.loading) {
        [self didUpdateInstantAnswers];
    }
}

- (UIScrollView *)scrollView {
    return _textView;
}

- (void)showActivityIndicator {
    UIActivityIndicatorView *activityView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    [activityView startAnimating];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:activityView];
}

- (void)hideActivityIndicator {
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedStringFromTable(@"Next", @"UserVoice", nil) style:UIBarButtonItemStyleDone target:self action:@selector(next)];
}

- (void)skipInstantAnswers {
    _detailsController = [UVDetailsFormViewController new];
    _detailsController.delegate = self;
    _detailsController.sendTitle = NSLocalizedStringFromTable(@"Send", @"UserVoice", nil);
    NSMutableArray *fields = [NSMutableArray array];
    for (UVCustomField *field in [UVSession currentSession].clientConfig.customFields) {
        NSMutableArray *values = [NSMutableArray array];
        if (!field.isRequired && field.isPredefined)
            [values addObject:@{@"id" : @"", @"label" : NSLocalizedStringFromTable(@"(none)", @"UserVoice", nil)}];
        for (NSString *value in field.values) {
            [values addObject:@{@"id" : value, @"label" : value}];
        }
        if (field.isRequired)
            [fields addObject:@{ @"name" : field.name, @"values" : values, @"required" : @(1) }];
        else
            [fields addObject:@{ @"name" : field.name, @"values" : values }];
    }
    _detailsController.fields = fields;
    _detailsController.selectedFieldValues = [NSMutableDictionary dictionary];
    for (NSString *key in [UVSession currentSession].config.customFields.allKeys) {
        NSString *value = [UVSession currentSession].config.customFields[key];
        _detailsController.selectedFieldValues[key] = @{ @"id" : value, @"label" : value };
    }
    [self.navigationController pushViewController:_detailsController animated:YES];
}

- (BOOL)validateCustomFields:(NSDictionary *)fields {
    for (UVCustomField *field in [UVSession currentSession].clientConfig.customFields) {
        if ([field isRequired]) {
            NSString *value = fields[field.name];
            if (!value || value.length == 0)
                return NO;
        }
    }
    return YES;
}

- (void)sendWithEmail:(NSString *)email name:(NSString *)name fields:(NSDictionary *)fields {
    if (_sending) return;
    NSMutableDictionary *customFields = [NSMutableDictionary dictionary];
    for (NSString *key in fields.allKeys) {
        customFields[key] = fields[key][@"label"];
    }
    self.userEmail = email;
    self.userName = name;
    if (![UVSession currentSession].user && email.length == 0) {
        [self alertError:NSLocalizedStringFromTable(@"Please enter your email address before submitting your ticket.", @"UserVoice", nil)];
    } else if (![self validateCustomFields:customFields]) {
        [self alertError:NSLocalizedStringFromTable(@"Please fill out all required fields.", @"UserVoice", nil)];
    } else {
        [_detailsController showActivityIndicator];
        _sending = YES;
        [UVTicket createWithMessage:_textView.text andEmailIfNotLoggedIn:email andName:name andCustomFields:customFields andDelegate:self];
    }
}

- (void)didCreateTicket:(UVTicket *)ticket {
    [self clearDraft];
    [UVBabayaga track:SUBMIT_TICKET];
    UVSuccessViewController *next = [UVSuccessViewController new];
    next.titleText = NSLocalizedStringFromTable(@"Message sent!", @"UserVoice", nil);
    next.text = NSLocalizedStringFromTable(@"We'll be in touch.", @"UserVoice", nil);
    [self.navigationController setViewControllers:@[next] animated:YES];
}

- (void)didReceiveError:(NSError *)error {
    _sending = NO;
    [_detailsController hideActivityIndicator];
    [super didReceiveError:error];
}

- (void)showSaveActionSheet {
    UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:nil
                                                             delegate:self
                                                    cancelButtonTitle:NSLocalizedStringFromTable(@"Cancel", @"UserVoice", nil)
                                               destructiveButtonTitle:NSLocalizedStringFromTable(@"Don't save", @"UserVoice", nil)
                                                    otherButtonTitles:NSLocalizedStringFromTable(@"Save draft", @"UserVoice", nil), nil];

    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        [actionSheet showFromBarButtonItem:self.navigationItem.leftBarButtonItem animated:YES];
    } else {
        [actionSheet showInView:self.view];
    }
}

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex {
    switch (buttonIndex) {
        case 0:
            [self clearDraft];
            [self dismissViewControllerAnimated:YES completion:nil];
            break;
        case 1:
            [self saveDraft];
            [self dismissViewControllerAnimated:YES completion:nil];
            break;
        default:
            break;
    }
}

- (void)clearDraft {
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    [prefs removeObjectForKey:@"uv-message-text"];
    [prefs synchronize];
}

- (void)loadDraft {
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    self.loadedDraft = _instantAnswerManager.searchText = _textView.text = [prefs stringForKey:@"uv-message-text"];
}

- (void)saveDraft {
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    [prefs setObject:_textView.text forKey:@"uv-message-text"];
    [prefs synchronize];
}

- (BOOL)shouldLeaveViewController {
    if (_textView.text.length == 0 || [_textView.text isEqualToString:_loadedDraft]) {
        return YES;
    } else {
        [self showSaveActionSheet];
        return NO;
    }
}

- (void)dismiss {
    if ([self shouldLeaveViewController])
        [self dismissViewControllerAnimated:YES completion:nil];
}

@end
