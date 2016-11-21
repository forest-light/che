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
package org.eclipse.che.ide.command.palette;

import com.google.gwt.core.client.GWT;
import com.google.gwt.event.dom.client.KeyUpEvent;
import com.google.gwt.uibinder.client.UiBinder;
import com.google.gwt.uibinder.client.UiField;
import com.google.gwt.uibinder.client.UiHandler;
import com.google.gwt.user.client.ui.TextBox;
import com.google.gwt.user.client.ui.Widget;
import com.google.inject.Inject;
import com.google.inject.Singleton;

import org.eclipse.che.ide.api.command.CommandType;
import org.eclipse.che.ide.api.command.CommandTypeRegistry;
import org.eclipse.che.ide.api.command.ContextualCommand;
import org.eclipse.che.ide.command.node.CommandTypeNode;
import org.eclipse.che.ide.command.node.ExecutableCommandNode;
import org.eclipse.che.ide.command.node.NodeFactory;
import org.eclipse.che.ide.ui.smartTree.NodeLoader;
import org.eclipse.che.ide.ui.smartTree.NodeStorage;
import org.eclipse.che.ide.ui.smartTree.Tree;
import org.eclipse.che.ide.ui.window.Window;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Implementation of {@link CommandsPaletteView}.
 *
 * @author Artem Zatsarynnyi
 */
@Singleton
public class CommandsPaletteViewImpl extends Window implements CommandsPaletteView {

    private static final CommandsPaletteViewImplUiBinder UI_BINDER = GWT.create(CommandsPaletteViewImplUiBinder.class);

    private final CommandTypeRegistry commandTypeRegistry;
    private final NodeFactory         nodeFactory;

    @UiField
    TextBox filterField;

    @UiField(provided = true)
    Tree commandsTree;

    private ActionDelegate delegate;

    @Inject
    public CommandsPaletteViewImpl(CommandTypeRegistry commandTypeRegistry, NodeFactory nodeFactory) {
        this.commandTypeRegistry = commandTypeRegistry;
        this.nodeFactory = nodeFactory;

        commandsTree = new Tree(new NodeStorage(), new NodeLoader());

        setWidget(UI_BINDER.createAndBindUi(this));

        setTitle("Commands Palette");

        filterField.getElement().setAttribute("placeholder", "Search command");
    }

    @Override
    public void show() {
        super.show();

        filterField.setValue("");
    }

    @Override
    public void close() {
        hide();
    }

    @Override
    public void setCommands(List<ContextualCommand> commands) {
        Map<CommandType, List<ContextualCommand>> commandsByType = new HashMap<>();

        for (ContextualCommand command : commands) {
            final CommandType commandType = commandTypeRegistry.getCommandTypeById(command.getType());
            List<ContextualCommand> commandsOfType = commandsByType.get(commandType);

            if (commandsOfType == null) {
                commandsOfType = new ArrayList<>();
                commandsByType.put(commandType, commandsOfType);
            }

            commandsOfType.add(command);
        }

        renderCommands(commandsByType);
    }

    @Override
    public String getFilterValue() {
        return filterField.getValue();
    }

    private void renderCommands(Map<CommandType, List<ContextualCommand>> commands) {
        commandsTree.getNodeStorage().clear();

        for (Map.Entry<CommandType, List<ContextualCommand>> entry : commands.entrySet()) {
            List<ExecutableCommandNode> commandNodes = new ArrayList<>(entry.getValue().size());
            for (ContextualCommand command : entry.getValue()) {
                commandNodes.add(nodeFactory.newExecutableCommandNode(command, null));
            }

            final CommandTypeNode commandTypeNode = nodeFactory.newCommandTypeNode(entry.getKey(), null, commandNodes);
            commandsTree.getNodeStorage().add(commandTypeNode);
        }

        commandsTree.expandAll();
    }

    @Override
    public void setDelegate(ActionDelegate delegate) {
        this.delegate = delegate;
    }

    @UiHandler({"filterField"})
    void onFilterChanged(@SuppressWarnings("UnusedParameters") KeyUpEvent event) {
        delegate.onFilterChanged(getFilterValue());
    }

    interface CommandsPaletteViewImplUiBinder extends UiBinder<Widget, CommandsPaletteViewImpl> {
    }
}