//
//  RxCollectionViewSectionedAnimatedDataSource.swift
//  RxExample
//
//  Created by Krunoslav Zaher on 7/2/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#if os(iOS) || os(tvOS)
import Foundation
import UIKit
#if !RX_NO_MODULE
import RxSwift
import RxCocoa
#endif
import Differentiator

/*
 This is commented becuse collection view has bugs when doing animated updates. 
 Take a look at randomized sections.
*/
open class RxCollectionViewSectionedAnimatedDataSource<S: AnimatableSectionModelType>
    : CollectionViewSectionedDataSource<S>
    , RxCollectionViewDataSourceType {
    public typealias Element = [S]
    public typealias DecideViewTransition = (CollectionViewSectionedDataSource<S>, UICollectionView, [Changeset<S>]) -> ViewTransition

    // animation configuration
    public var animationConfiguration: AnimationConfiguration

    /// Calculates view transition depending on type of changes
    public var decideViewTransition: DecideViewTransition

    private let scheduler: ImmediateSchedulerType

    
    public init(
        animationConfiguration: AnimationConfiguration = AnimationConfiguration(),
        decideViewTransition: @escaping DecideViewTransition = { _, _, _ in .animated },
        configureCell: @escaping ConfigureCell,
        configureSupplementaryView: @escaping ConfigureSupplementaryView,
        moveItem: @escaping MoveItem = { _, _, _ in () },
        canMoveItemAtIndexPath: @escaping CanMoveItemAtIndexPath = { _, _ in false },
        scheduler: ImmediateSchedulerType = MainScheduler.instance
        ) {
        self.animationConfiguration = animationConfiguration
        self.decideViewTransition = decideViewTransition
        self.scheduler = scheduler
        super.init(
            configureCell: configureCell,
            configureSupplementaryView: configureSupplementaryView,
            moveItem: moveItem,
            canMoveItemAtIndexPath: canMoveItemAtIndexPath
        )

        self.updateEvent
            .map({ (updates) -> (RxCollectionViewSectionedAnimatedDataSource<S>,UICollectionView, [SectionModelSnapshot]) in
                let (dataSource, collectionView, newSections) = updates
                return (dataSource, collectionView, newSections.map { SectionModelSnapshot(model: $0, items: $0.items) })
            })
            //.observeOn(scheduler) // updateEvent already called on sheduler!
            .scan(nil, accumulator: { (accum, updates) -> (RxCollectionViewSectionedAnimatedDataSource<S>,UICollectionView,[Changeset<S>], [SectionModelSnapshot], Bool) in
                let (dataSource, collectionView, newSectionsModel) = updates

                if let (_, _, _, oldSections,_) = accum {
                    do {
                        let differences = try Diff.differencesForSectionedView(initialSections: oldSections.map { Section(original: $0.model, items: $0.items) },
                                                                               finalSections: newSectionsModel.map { Section(original: $0.model, items: $0.items) })
                        let reloadAllFalse = false
                        return (dataSource,collectionView,differences,newSectionsModel,reloadAllFalse)
                    }catch let e {
                        #if DEBUG
                            print("Error while calculating differences.")
                            rxDebugFatalError(e)
                        #endif
                        let reloadAllTrue = true
                        return (dataSource,collectionView,[Changeset<S>](),oldSections, reloadAllTrue)
                    }
                }else {
                    let reloadAll = true
                    return (dataSource, collectionView,[Changeset<S>](),newSectionsModel, reloadAll)
                }
            })
            .observeOn(MainScheduler.asyncInstance)
            .throttle(0.5, scheduler: MainScheduler.instance)
            .subscribe(onNext:{ event in
                let (dataSource, collectionView, differences, newSections, reloadAll) = event!

                if collectionView.window == nil || reloadAll {
                    dataSource.setSectionModels(newSections)
                    collectionView.reloadData()
                    return
                }
                
                switch dataSource.decideViewTransition(dataSource, collectionView, differences) {
                case .animated:
                    for difference in differences {
                        dataSource.setSections(difference.finalSections)
                        collectionView.performBatchUpdates(difference, animationConfiguration: dataSource.animationConfiguration)
                    }
                case .reload:
                    dataSource.setSectionModels(newSections)
                    collectionView.reloadData()
                }
                
            })
            .disposed(by: disposeBag)
    }

    private let disposeBag = DisposeBag()

    // This subject and throttle are here
    // because collection view has problems processing animated updates fast.
    // This should somewhat help to alleviate the problem.
    
    typealias UpdateEventType = (RxCollectionViewSectionedAnimatedDataSource<S>,UICollectionView, Element)
    private let updateEvent = PublishSubject<UpdateEventType>()


    open func collectionView(_ collectionView: UICollectionView, observedEvent: Event<Element> ) {
        Binder(self,scheduler: self.scheduler) { dataSource, newSections in
            #if DEBUG
                self._dataSourceBound = true
            #endif
            let updates = (dataSource, collectionView, newSections)
            dataSource.updateEvent.on(.next(updates))
        }.on(observedEvent)
    }
}
#endif
