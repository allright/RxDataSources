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
            //.observeOn(scheduler) // updateEvent already called on sheduler!
            .scan(nil, accumulator: { (accum, updates) -> (RxCollectionViewSectionedAnimatedDataSource<S>,UICollectionView,[Changeset<S>], [SectionModelSnapshot], Bool) in
                let (dataSource, collectionView, newSections) = updates

                if let (_, _, _, sectionModels,_) = accum {
                    NSLog("next!")
                    let oldSections = sectionModels.map { Section(original: $0.model, items: $0.items) }
                    do {
                        let differences = try Diff.differencesForSectionedView(initialSections: oldSections, finalSections: newSections)
                        let reloadAllFalse = false
                        return (dataSource,collectionView,differences,newSections.map { SectionModelSnapshot(model: $0, items: $0.items) },reloadAllFalse)
                    }catch let e {
                        #if DEBUG
                            print("Error while calculating differences.")
                            rxDebugFatalError(e)
                        #endif
                        let reloadAllTrue = true
                        return (dataSource,collectionView,[Changeset<S>](),oldSections.map { SectionModelSnapshot(model: $0, items: $0.items) }, reloadAllTrue)
                    }
                }else {
                    NSLog("init!")
                    let reloadAll = true
                    return (dataSource, collectionView,[Changeset<S>](),newSections.map { SectionModelSnapshot(model: $0, items: $0.items) }, reloadAll)
                }
            })
            .observeOn(MainScheduler.asyncInstance)
            .throttle(0.5, scheduler: MainScheduler.instance)
            .subscribe(onNext:{ event in
                let (dataSource,collectionView, differences, newSections, reloadAll) = event!

                if collectionView.window == nil || reloadAll {
                    dataSource.setSections(newSections.map { Section(original: $0.model, items: $0.items) })
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
                    dataSource.setSections(newSections.map { Section(original: $0.model, items: $0.items) })
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
    /**
     This method exists because collection view updates are throttled because of internal collection view bugs.
     Collection view behaves poorly during fast updates, so this should remedy those issues.
    */
    open func collectionView(_ collectionView: UICollectionView, throttledObservedEvent event: Event<Element>) {
        Binder(self) { dataSource, newSections in
            let oldSections = dataSource.sectionModels
            do {
                // if view is not in view hierarchy, performing batch updates will crash the app
                if collectionView.window == nil {
                    dataSource.setSections(newSections)
                    collectionView.reloadData()
                    return
                }
                let differences = try Diff.differencesForSectionedView(initialSections: oldSections, finalSections: newSections)

                switch self.decideViewTransition(self, collectionView, differences) {
                case .animated:
                    for difference in differences {
                        dataSource.setSections(difference.finalSections)

                        collectionView.performBatchUpdates(difference, animationConfiguration: self.animationConfiguration)
                    }
                case .reload:
                    self.setSections(newSections)
                    collectionView.reloadData()
                }
            }
            catch let e {
                #if DEBUG
                    print("Error while binding data animated: \(e)\nFallback to normal `reloadData` behavior.")
                    rxDebugFatalError(e)
                #endif
                self.setSections(newSections)
                collectionView.reloadData()
            }
        }.on(event)
    }

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
