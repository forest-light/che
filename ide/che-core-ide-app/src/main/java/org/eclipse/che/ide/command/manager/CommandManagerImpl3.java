/*******************************************************************************
 * Copyright (c) 2012-2016 Codenvy, S.A.
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License v1.0
 * which accompanies this distribution, and is available at
 * http://www.eclipse.org/legal/epl-v10.html
 *
 * Contributors:
 *   Codenvy, S.A. - initial API and implementation
 *******************************************************************************/
package org.eclipse.che.ide.command.manager;

import elemental.util.ArrayOf;

import com.google.gwt.core.client.Callback;
import com.google.inject.Inject;
import com.google.web.bindery.event.shared.EventBus;

import org.eclipse.che.api.promises.client.Function;
import org.eclipse.che.api.promises.client.FunctionException;
import org.eclipse.che.api.promises.client.Operation;
import org.eclipse.che.api.promises.client.OperationException;
import org.eclipse.che.api.promises.client.Promise;
import org.eclipse.che.api.promises.client.PromiseProvider;
import org.eclipse.che.api.promises.client.js.JsPromiseError;
import org.eclipse.che.commons.annotation.Nullable;
import org.eclipse.che.ide.api.app.AppContext;
import org.eclipse.che.ide.api.command.ApplicableContext;
import org.eclipse.che.ide.api.command.CommandImpl;
import org.eclipse.che.ide.api.command.CommandManager3;
import org.eclipse.che.ide.api.command.CommandPage;
import org.eclipse.che.ide.api.command.CommandType;
import org.eclipse.che.ide.api.command.CommandTypeRegistry;
import org.eclipse.che.ide.api.command.CommandWithContext;
import org.eclipse.che.ide.api.component.WsAgentComponent;
import org.eclipse.che.ide.api.resources.Project;
import org.eclipse.che.ide.api.workspace.WorkspaceReadyEvent;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import static com.google.common.base.Strings.isNullOrEmpty;
import static org.eclipse.che.api.workspace.shared.Constants.COMMAND_PREVIEW_URL_ATTRIBUTE_NAME;

/**
 * Implementation of {@link CommandManager3}.
 *
 * @author Artem Zatsarynnyi
 */
public class CommandManagerImpl3 implements CommandManager3, WsAgentComponent, WorkspaceReadyEvent.WorkspaceReadyHandler {

    private final CommandTypeRegistry             commandTypeRegistry;
    private final AppContext                      appContext;
    private final ProjectCommandManagerDelegate   projectCommandManagerDelegate;
    private final WorkspaceCommandManagerDelegate workspaceCommandManagerDelegate;
    private final PromiseProvider                 promiseProvider;

    private final Map<String, CommandWithContext> commands;

    private final Set<CommandChangedListener> commandChangedListeners;

    @Inject
    public CommandManagerImpl3(CommandTypeRegistry commandTypeRegistry,
                               AppContext appContext,
                               ProjectCommandManagerDelegate projectCommandManagerDelegate,
                               WorkspaceCommandManagerDelegate workspaceCommandManagerDelegate,
                               PromiseProvider promiseProvider,
                               EventBus eventBus) {
        this.commandTypeRegistry = commandTypeRegistry;
        this.appContext = appContext;
        this.projectCommandManagerDelegate = projectCommandManagerDelegate;
        this.workspaceCommandManagerDelegate = workspaceCommandManagerDelegate;
        this.promiseProvider = promiseProvider;

        commands = new HashMap<>();

        commandChangedListeners = new HashSet<>();

        eventBus.addHandler(WorkspaceReadyEvent.getType(), this);
    }

    @Override
    public void onWorkspaceReady(WorkspaceReadyEvent event) {
        fetchCommands();
    }

    private void fetchCommands() {
        workspaceCommandManagerDelegate.getCommands(appContext.getWorkspaceId()).then(new Operation<List<CommandImpl>>() {
            @Override
            public void apply(List<CommandImpl> arg) throws OperationException {
                for (CommandImpl command : arg) {
                    final CommandWithContext commandWithContext = new CommandWithContext(command);
                    final ApplicableContext applicableContext = commandWithContext.getApplicableContext();
                    applicableContext.setWorkspaceApplicable(true);

                    commands.put(command.getName(), commandWithContext);
                }

                for (Project project : appContext.getProjects()) {
                    for (CommandImpl projectCommand : projectCommandManagerDelegate.getCommands(project)) {
                        CommandWithContext commandWithContext = commands.get(projectCommand.getName());
                        if (commandWithContext == null) {
                            commandWithContext = new CommandWithContext(projectCommand);

                            commands.put(commandWithContext.getName(), commandWithContext);
                        }

                        commandWithContext.getApplicableContext().addApplicableProject(project.getPath());
                    }
                }
            }
        });
    }

    @Override
    public List<CommandWithContext> getCommands() {
        // return copy of the commands in order to prevent it modification directly
        List<CommandWithContext> list = new ArrayList<>(commands.size());
        for (CommandWithContext command : commands.values()) {
            list.add(command);
        }

        return list;
    }

    @Override
    public Promise<CommandWithContext> createCommand(final String type, final ApplicableContext applicableContext) {
        return createCommand(new CommandWithContext(getUniqueCommandName(type, "name"), "cmd", type));
    }

    @Override
    public Promise<CommandWithContext> createCommand(CommandWithContext command) {
        final String type = command.getType();
        final ApplicableContext applicableContext = command.getApplicableContext();

        final CommandType commandType = commandTypeRegistry.getCommandTypeById(type);

        // should not happen, but let's play safe
        if (commandType == null) {
            return promiseProvider.reject(JsPromiseError.create("Can't create command. Unknown command type: " + type));
        }

        final CommandWithContext cmdWithCntx = new CommandWithContext(getUniqueCommandName(type, "name"), "cmd", type);

        cmdWithCntx.getAttributes().put(COMMAND_PREVIEW_URL_ATTRIBUTE_NAME, commandType.getPreviewUrlTemplate());

        final List<Promise<CommandImpl>> commandPromises = new ArrayList<>();

        if (applicableContext.isWorkspaceApplicable()) {
            Promise<CommandImpl> p = workspaceCommandManagerDelegate.createCommand(cmdWithCntx).then(new Operation<CommandImpl>() {
                @Override
                public void apply(CommandImpl arg) throws OperationException {
                    cmdWithCntx.getApplicableContext().setWorkspaceApplicable(true);
                }
            });

            commandPromises.add(p);
        }

        for (final String projectPath : applicableContext.getApplicableProjects()) {
            final Project project = getProjectByPath(projectPath);

            Promise<CommandImpl> p = projectCommandManagerDelegate.createCommand(project, cmdWithCntx).then(new Operation<CommandImpl>() {
                @Override
                public void apply(CommandImpl arg) throws OperationException {
                    cmdWithCntx.getApplicableContext().addApplicableProject(projectPath);
                }
            });

            commandPromises.add(p);
        }

        Promise[] promisesArray = new Promise[commandPromises.size()];
        for (Promise<CommandImpl> commandPromise : commandPromises) {
            promisesArray[commandPromises.indexOf(commandPromise)] = commandPromise;
        }

        return promiseProvider.all2(promisesArray).then(new Function<ArrayOf<?>, CommandWithContext>() {
            @Override
            public CommandWithContext apply(ArrayOf<?> ignore) throws FunctionException {
                commands.put(cmdWithCntx.getName(), cmdWithCntx);

                notifyCommandAdded(cmdWithCntx);

                return cmdWithCntx;
            }
        });
    }

    @Nullable
    private Project getProjectByPath(String path) {
        for (Project project : appContext.getProjects()) {
            if (path.equals(project.getPath())) {
                return project;
            }
        }

        return null;
    }

    @Override
    public Promise<CommandWithContext> updateCommand(String commandName, final CommandWithContext command) {

        // TODO
        // if renamed - remove/create
        // if applicable context changed - remove/create
        // in other cases - just update

        final CommandWithContext cmdWithCntx = commands.get(commandName);

        if (cmdWithCntx == null) {
            return promiseProvider.reject(JsPromiseError.create("Can't update command. Command " + commandName + " not found."));
        }

        final ApplicableContext applicableContext = cmdWithCntx.getApplicableContext();

        List<Promise<CommandImpl>> commandPromises = new ArrayList<>();

        if (applicableContext.isWorkspaceApplicable()) {
            Promise<CommandImpl> p = workspaceCommandManagerDelegate.updateCommand(commandName, command).then(new Operation<CommandImpl>() {
                @Override
                public void apply(CommandImpl arg) throws OperationException {
                    // TODO
                }
            });

            commandPromises.add(p);
        }

        for (final String projectPath : applicableContext.getApplicableProjects()) {
            final Project project = getProjectByPath(projectPath);

            if (project != null) {
                Promise<CommandImpl> p =
                        projectCommandManagerDelegate.updateCommand(project, commandName, command).then(new Operation<CommandImpl>() {
                            @Override
                            public void apply(CommandImpl arg) throws OperationException {
                                // TODO
                            }
                        });

                commandPromises.add(p);
            }
        }

        Promise[] projectPromisesArray = new Promise[commandPromises.size()];
        for (Promise<CommandImpl> commandPromise : commandPromises) {
            projectPromisesArray[commandPromises.indexOf(commandPromise)] = commandPromise;
        }

        return promiseProvider.all2(projectPromisesArray).then(new Function<ArrayOf<?>, CommandWithContext>() {
            @Override
            public CommandWithContext apply(ArrayOf<?> ignore) throws FunctionException {

                // TODO
//                commands.remove(cmdWithCntx.getName());

                notifyCommandUpdated(cmdWithCntx);

                return cmdWithCntx;
            }
        });
    }

    @Override
    public Promise<Void> removeCommand(final String commandName) {
        final CommandWithContext cmdWithCntx = commands.get(commandName);

        if (cmdWithCntx == null) {
            return promiseProvider.reject(JsPromiseError.create("Can't remove command. Command " + commandName + " not found."));
        }

        final ApplicableContext applicableContext = cmdWithCntx.getApplicableContext();

        List<Promise<Void>> commandPromises = new ArrayList<>();

        if (applicableContext.isWorkspaceApplicable()) {
            commandPromises.add(workspaceCommandManagerDelegate.removeCommand(commandName));
        }

        for (final String projectPath : applicableContext.getApplicableProjects()) {
            final Project project = getProjectByPath(projectPath);

            if (project != null) {
                commandPromises.add(projectCommandManagerDelegate.removeCommand(project, commandName));
            }
        }

        Promise[] projectPromisesArray = new Promise[commandPromises.size()];
        for (Promise<Void> commandPromise : commandPromises) {
            projectPromisesArray[commandPromises.indexOf(commandPromise)] = commandPromise;
        }

        return promiseProvider.all2(projectPromisesArray).then(new Function<ArrayOf<?>, Void>() {
            @Override
            public Void apply(ArrayOf<?> ignore) throws FunctionException {
                commands.remove(cmdWithCntx.getName());

                notifyCommandRemoved(cmdWithCntx);

                return null;
            }
        });
    }

    @Override
    public List<CommandPage> getPages(String type) {
        CommandType commandType = commandTypeRegistry.getCommandTypeById(type);
        return commandType != null ? commandType.getPages() : Collections.<CommandPage>emptyList();
    }

    @Override
    public void addCommandChangedListener(CommandChangedListener listener) {
        commandChangedListeners.add(listener);
    }

    @Override
    public void removeCommandChangedListener(CommandChangedListener listener) {
        commandChangedListeners.remove(listener);
    }

    private void notifyCommandAdded(CommandImpl command) {
        for (CommandChangedListener listener : commandChangedListeners) {
            listener.onCommandAdded(command);
        }
    }

    private void notifyCommandRemoved(CommandImpl command) {
        for (CommandChangedListener listener : commandChangedListeners) {
            listener.onCommandRemoved(command);
        }
    }

    private void notifyCommandUpdated(CommandImpl command) {
        for (CommandChangedListener listener : commandChangedListeners) {
            listener.onCommandUpdated(command);
        }
    }

    /**
     * Returns {@code customName} if it's unique within the given {@code customType}
     * or newly generated name if it isn't unique within the given {@code customType}.
     */
    private String getUniqueCommandName(String customType, String customName) {
        final CommandType commandType = commandTypeRegistry.getCommandTypeById(customType);
        final Set<String> commandNames = commands.keySet();

        final String newCommandName;

        if (isNullOrEmpty(customName)) {
            newCommandName = "new" + commandType.getDisplayName();
        } else {
            if (!commandNames.contains(customName)) {
                return customName;
            }
            newCommandName = customName + " copy";
        }

        if (!commandNames.contains(newCommandName)) {
            return newCommandName;
        }

        for (int count = 1; count < 1000; count++) {
            if (!commandNames.contains(newCommandName + "-" + count)) {
                return newCommandName + "-" + count;
            }
        }

        return newCommandName;
    }

    // TODO: just for eager instantiating
    @Override
    public void start(Callback<WsAgentComponent, Exception> callback) {
        callback.onSuccess(this);
    }
}
