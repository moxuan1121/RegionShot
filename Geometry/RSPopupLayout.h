#pragma once
#import <UIKit/UIKit.h>
#import "RSGeometry.h"
static inline CGFloat RSPopupContentHeight(UIStackView *stack, UIView *content, CGFloat width, CGFloat available, CGFloat requested, CGFloat percent) {
    CGFloat body = 0;
    if ([content isKindOfClass:UICollectionView.class]) {
        UICollectionView *list = (id)content;
        list.bounds = CGRectMake(0, 0, width, MAX(1, available));
        [list.collectionViewLayout invalidateLayout];
        [list layoutIfNeeded];
        body = list.collectionViewLayout.collectionViewContentSize.height;
    } else body = [content sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)].height;
    CGFloat chrome = 60;
    NSUInteger count = 0;
    for (UIView *view in stack.arrangedSubviews) {
        if (view.hidden) continue;
        count++;
        if (view != content) chrome += [view systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    }
    if (count > 1) chrome += (count - 1) * stack.spacing;
    return RSSharedPopupHeight(body, chrome, available, requested, percent);
}
